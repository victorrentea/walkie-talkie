import AppKit

/// **The gestures that work right now, bottom right of the screen** (2026-09-29).
///
/// Victor: *"during dictation, show a small hint bar in the bottom right of the
/// screen with the key combos available at that stage (eg 🔽↑ stop video,
/// 🔼 end dictation...)"*. The chip by the pointer says what the sentence *is*;
/// this says what he can *do* to it, and changes with the stage: a prompt
/// offers the shutter, the film, kamikaze and a new session; a plain dictation
/// only its stop, its stop-and-Return and the cancel.
///
/// **Drawn as two crosses, one per side button** (2026-09-30, from his sketch):
/// 🔼 on top, 🔽 under it, as the buttons sit on the mouse. The centre box is the
/// click, the arms are the swipes, and a gesture with nothing to do right now
/// keeps an empty box so the shape — and where his thumb goes — never moves.
/// 🔼 → has no box at all: mid-sentence it flips bound ⇄ caret (2026-10-05),
/// which the chip's destination row already shows.
///
/// **Off the Retina, against its edge** (2026-09-30, Victor: *"displayed on any
/// secondary monitor if there are any, otherwise on the Retina. Prefer the monitor
/// to the right of Retina. Keep them small and close to the edge which is adjoined
/// to Retina"*). The Retina is where he works; the bar sits just across the seam,
/// bottom of that seam, so a glance sideways finds it. See `placement`.
///
/// **Three times bigger off the Retina** (2026-10-01, Victor: *"when the shortcuts
/// appear on the secondary screen, make them twice as big. Even three times. Plenty
/// of room, so I see them easily. If it's not on the Retina."*). A glance sideways
/// at a farther, low-density screen needs the size; on the Retina it stays small.
///
/// **Opaque across the seam; when the pointer follows it there, it flees back**
/// (2026-10-01, Victor: *"when the hints appear on the other screen, fully opaque.
/// My mouse goes there, but they should come back to the other screen, even on the
/// side if needed. But there extremely transparent, flee from the screen the mouse
/// is on"*). Off the Retina nothing is underneath that he is looking at, so it is
/// solid; once the pointer is on that screen it is in the way, so it moves to the
/// Retina's side of the same seam, small and nearly see-through. See `spot`.
///
/// **Alone, it hides from the pointer** (2026-10-08): with one screen there is
/// nowhere to flee, so the pointer within `dodge` of the corner fades it out
/// and leaving fades it back. See `spot`.
///
/// Only in Logi mode — the glyphs are the side buttons' (`GestureGuide.logiGesturesOn`).
/// Never in a screenshot (`sharingType = .none`), never takes the mouse, and it
/// does not ride the pointer: a fixed spot, so it is read at a glance.
final class GestureHintBar {

    /// What the chip knows about the sentence, which is all the bar needs.
    struct Stage: Equatable {
        var listening = false
        /// A prompt (🔼 / 🔼 → / 🔼 ↑); false for a plain dictation.
        var prompting = false
        var filming = false
        var kamikaze = false
        /// The sentence goes to the bound terminal: 🔽 ← marks it 🛑 interrupt
        /// (2026-11-22, `InterruptGate`); `interrupt` = already marked.
        var interruptible = false
        var interrupt = false
        /// The sentence already opens a new session — 🔼 ↑ has nothing left to do.
        var spawn = false
        /// Right ⌘⌥ is held for it: his hand is on the keyboard, not the mouse,
        /// so there is nothing to show (2026-09-30, Victor: *"no need to display
        /// those shortcuts while cmd-opt pressed down dictation"*).
        var held = false
        /// A wheel crop is on screen: the bar draws the mouse instead of the two
        /// side buttons, because that is the hand the crop is in (2026-10-07).
        var crop: CropPhase? = nil
        /// A ⚡ quick question: its stop asks the model, nothing is typed and
        /// no Return follows (2026-10-09); a prompt's gestures since 2026-10-15.
        var quick = false
        /// Left ⌃⌥⌘ held past `HotkeyTap.trackpadHintDelay`: the crosses are the
        /// trackpad's — ☝️ one finger for 🔼, ✌️ two for 🔽 — at rest too
        /// (2026-10-20, `fingerCrosses`).
        var fingers = false
        /// No Logitech mouse attached (`MouseDevices`): a sentence's bar is the
        /// trackpad's, under the chord or not — the side buttons are not there.
        var noMouse = false
    }

    /// Where the wheel crop is — `CropSelectionOverlay.Phase`, without `done`.
    enum CropPhase: Equatable { case selecting, locked, parked, drawing }

    /// **The mouse, drawn, for the length of a crop** (2026-10-07). Victor, on
    /// the right click that now locks the box: *"aș vrea să poți să reprezinți
    /// chestia asta cumva vizual … pe acele hint-uri"*. Same rules as a cross:
    /// `""` is an empty gray box (the button does nothing right now).
    struct MouseHint: Equatable {
        var left = ""
        var wheel = ""
        var right = ""
        /// Under the buttons, on the mouse's body: the keyboard's way out.
        var body = ""
    }

    /// The mouse for a stage, or nil when no crop is up. Pure, like `crosses`.
    static func mouse(for s: Stage) -> MouseHint? {
        guard s.listening, !s.held, let crop = s.crop else { return nil }
        switch crop {
        case .selecting:
            // **🔽 ↑ with the wheel still down films this box** (2026-11-22,
            // `HotkeyTap.onAreaFilm`) — on the mouse's body, where the thumb is.
            // Not over a ⚡ question (no film there), not without the mouse.
            return MouseHint(wheel: "✂️ drag", right: "➡️ move to",
                             body: s.noMouse || s.quick ? "Esc cancel" : Self.filmTheBox + " Esc cancel")
        case .locked:
            return MouseHint(wheel: "⬆️ let go", right: "↩️ unlock", body: "Esc cancel")
        case .parked:
            // A left click drops the half-transparent copy riding the pointer
            // (2026-10-19, `CropSelectionOverlay.leftClicked`).
            return MouseHint(left: "📍 drop", wheel: "🎯 drag there", right: "🗑️ discard", body: "Esc cancel")
        case .drawing:
            // The right button is not taken while the destination is drawn: it
            // cancels, as parked (2026-10-25, the hint audit).
            return MouseHint(wheel: "🎯 drag there", right: "🗑️ discard", body: "Esc cancel")
        }
    }

    /// The crop's body while the box is dragged: 🔽 ↑ films it.
    static let filmTheBox = "🔽↑ 🔴 video"

    /// One button's gestures. `nil` = no box is drawn, `""` = an empty box.
    struct Cross: Equatable {
        var click: String? = ""
        var up: String? = ""
        var down: String? = ""
        var left: String? = ""
        var right: String? = ""
        /// Drawn big and boxless in the top-left cell — the trackpad's finger
        /// (2026-10-20, Victor: *"just move the emoji showing how many fingers …
        /// out of any other badge … left top"*).
        var corner: String? = nil
    }

    /// The two crosses for a stage — 🔼 first, 🔽 second. Pure, so the wording
    /// can be checked without a screen.
    static func crosses(for s: Stage) -> [Cross] {
        guard s.listening, !s.held else { return [] }
        var front = Cross(right: nil)
        var back = Cross()
        front.left = "🗑️ discard"
        // **Every gesture that acts, labelled, in every stage** (2026-10-25, Victor:
        // *"Am dat Forward sus și mi-a trecut ask în modul de terminal nou. Am dat
        // back stânga și mi-a făcut cancel. Ăsta n-apar pe … diagrama de butoane
        // live"*). Three audits traced each F-key to its handler: 🔽 ← cancels any
        // open microphone (2026-10-21) and 🔼 ↑ makes any sentence a new-session
        // prompt — neither was drawn outside a prompt, 🔽 ← nowhere.
        // 🔽 ← does nothing mid-sentence since 2026-11-21 — 🔼 ← is the cancel.
        // …except over a sentence bound for the terminal: 🛑 interrupt (2026-11-22),
        // crossed out once it is on, as kamikaze.
        back.left = s.interruptible && !s.quick ? (s.interrupt ? Self.struck + "🛑" : "🛑 interrupt") : ""
        front.up = s.spawn ? "📂 folder" : "✨ new"
        if s.prompting {
            front.click = "🏁 end"
            // Kamikaze is its emoji alone, crossed out once it is on (2026-09-30,
            // Victor: *"instead of 'no kamikaze', kamikaze crossed out"*).
            front.down = s.kamikaze ? Self.struck + "☠️" : "☠️"
            // 🔼 → flips bound ⇄ caret, which the chip shows — no box; a spawn has
            // nothing to flip to, and ends (`toggleDictation(flipsDestination:)`).
            if s.spawn { front.right = "🏁 end" }
            // While a film runs the shutter is its stop (2026-10-23, `onScreenshot`).
            back.click = s.filming ? "⏹️ video" : "📸 shot"
            // Stop is ⏹️, never the word (2026-09-30).
            // Always the whole display here (2026-11-22): a box is filmed from
            // inside its own wheel drag (`mouse(for:)`), no longer *after a crop*.
            back.up = s.filming ? "⏹️ video" : "🔴 video"
            // The typing box (2026-10-08, Victor: *"nu-l văd nici în sugestia
            // de taste din colț"*) — `HotkeyTap.onTypeIn`.
            back.down = "⌨️ type"
            // 🧠 The session's model, round the ring Opus / high → Fable / medium →
            // Sonnet / high (2026-11-21, three since 2026-11-22 — `ModelSwitch`).
            back.right = "🧠 model"
        } else if s.quick {
            // **A question is a prompt** (2026-10-15): 🔼 asks, 🔽 is the
            // shutter and ↓ the typing box, as while prompting; no kamikaze, no
            // film (`toggleFilm` refuses it) — a question's answer is the reply
            // pop-up. 🔽 → Googles it instead (2026-10-25, `onQuickGoogle`); 🔼 ↓ does both.
            // **Neither ✨ nor the terminal is offered from a question** (2026-11-22,
            // Victor: *"din modul question nu are sens să am ✨ sau prompt bound"*):
            // both arms are grey boxes. The bar only — 🔼 ↑ and 🔼 → still redirect
            // the question (`convertDictationToSpawn`, `retarget` → `dropQuestion`).
            front.click = "⚡ ask"
            // 🔼 ↓ Googles it AND answers it (2026-11-11, `quickGoogleToo`).
            front.down = Self.google + " + ⚡"
            front.up = ""
            front.right = ""
            back.click = "📸 shot"
            back.up = ""
            back.down = "⌨️ type"
            back.right = Self.google + " Google"
        } else {
            // **A plain sentence has a cancel and a stop, nothing else** (2026-11-22,
            // Victor: *"dictation mai are doar cancel 🗑️ și stop pe butonul de forward
            // sau back. atât."*): 🔼 ← discards, 🔼 and 🔽 stop it — the words, then
            // Return — and every other arm is a grey box (`HotkeyTap.plainIgnores`).
            front.click = "⏹️ + ⏎"
            front.up = ""
            front.down = ""
            front.right = ""
            back.click = "⏹️ + ⏎"
            back.left = ""
            back.down = ""
            back.right = ""
        }
        // **The keyboard's way beside the gesture it stands for** (2026-10-20 on
        // the trackpad's crosses, on the mouse's too since 2026-10-22, Victor:
        // *"să-mi apară și shortcut-urile … pe care le pot apăsa"*): right ⌘ ×2
        // ends a prompt (and stops a plain sentence without a Return), ⌃P is the
        // shutter while a prompt records.
        // **The emoji, a slash, the key** for the end and the shot (2026-10-23,
        // Victor: *"Lasă doar steagul de finish … taie cu shot și lasă doar un
        // slash între ele"*) — `🏁 / ⌘⌘`, `📸 / ⌃P`; the words went.
        if front.click == "🏁 end" { front.click = "🏁 / ⌘⌘" }
        else if s.prompting || s.quick { front.click = (front.click ?? "") + " ⌘⌘" }
        if back.click == "📸 shot" { back.click = "📸 / ⌃P" }
        else if s.prompting, s.filming { back.click = "⏹️ / ⌃P" }
        // Right ⌘ ×2 stops a plain sentence as the bare 🔽 does (Return and all).
        if !s.prompting && !s.quick { back.click = "⏹️ + ⏎ ⌘⌘" }
        return [front, back]
    }

    /// **The keys with no gesture behind them, in a row under the crosses**
    /// (2026-10-22, Victor: *"inventează … cum aș putea să [trec din dictare în
    /// promptare] din taste și … să-mi apară în tooltip-urile din dreapta"*).
    /// ⌃P over a plain dictation makes it a prompt at the caret and takes the
    /// shot (`HotkeyTap.onPlainToPrompt`); ⌘C files what he copies — into a
    /// prompt, and gathered by a plain one for the moment it becomes one. Pure.
    static func keys(for s: Stage) -> [String] {
        guard s.listening, !s.held, s.crop == nil else { return [] }
        // A prompt (a ⚡ question is one) files what he highlights too — the
        // selection watcher runs on `attachable`, which a plain sentence is not
        // (`AppDelegate.syncBorrowedGestures`); the clipboard's runs for both.
        // **Copy always in the bottom-right corner, select in the centre**
        // (2026-11-22, Victor: *"copy să fie mereu în colț dreapta jos. text
        // selection să vină pe centru"*) — the row is right-aligned, so last = corner.
        if s.prompting || s.quick { return [selectKey, copyKey] }
        // **No copy on a plain dictation's bar** (2026-11-22, Victor: *"ce sens are
        // copy în plain dictation?? … scoate, că nu are sens. dictez doar"*). The
        // **Nor `💬 prompt ⌃P`** (same day, *"scoate și ctrl-p"*): ⌃P no longer
        // turns a plain dictation into a prompt, and it gathers no copies either.
        return []
    }

    static let promptKey = "💬 prompt ⌃P"
    /// **Copy is its icon alone — no word, no ⌘C** (2026-11-22, Victor: *"pune
    /// iconița de Copy care e standard, cele două dreptunghiuri cumva rotunjite …
    /// la copy jos nici nu mai spui Command [C]"*): the Edit menu's two sheets
    /// (`doc.on.doc`, as on the chip since 2026-10-29), painted where this
    /// private-use character stands. `📋 copy ⌘C` until then.
    static let copyKey = "\u{E0A1}"
    /// **Select: a caret dragging over lines of text** (2026-11-22, Victor: *"mai
    /// pune-mi încă un badge … select. Să aibă un caret și niște texte pe care
    /// tragi"*) — `Glyphs.select`, painted where this character stands.
    static let selectKey = "\u{E0A2}"
    /// **To the bound terminal: a drawn `>_` window, not 💻** (2026-11-22,
    /// Victor: *"ce înseamnă 💻 în aceste poze?"* — and 💻 is the local model on
    /// the chip). `Glyphs.terminal`, painted where this character stands.
    static let terminal = "\u{E0A3}"

    // MARK: glyphs with the mouse, keys without it (2026-11-22)

    /// **What a label shows.** Victor: *"afișează tastele, adică Command Command
    /// pentru finish, Control P pentru poză, doar dacă nu e mouse-ul conectat.
    /// Dacă e mouse-ul conectat, nu mă ajută. Alea, lasă doar emoji-urile …
    /// cred că poți chiar să scoți textele cu totul … mai puțin late acele
    /// badge-uri."* `crosses` / `mouse` / `keys` keep the full wording (it is the
    /// spec, and the log's); this cuts it for the screen:
    /// - **the words go, always** — `🗑️ discard` → `🗑️`, `🔴 ✂️ video` → `🔴 ✂️`;
    ///   a `+` stays only between two glyphs (`⏹️ + ⏎`);
    /// - **a key legend** (a token with ⌘ ⌃ ⌥ ⇧, or `Esc`) **stays only with
    ///   `keys`** — no Logitech mouse — after a slash: `🏁 / ⌘⌘`, `⚡ / ⌘⌘`;
    /// - **a label with no glyph keeps its words** (a glyph cannot be invented
    ///   here) — unless it names a key and keys are off: then it is empty.
    /// Pure.
    static func shown(_ label: String, keys showKeys: Bool) -> String {
        var glyphs: [String] = [], legend: [String] = []
        var joiner = false
        for token in label.split(separator: " ") {
            if isKey(token) { legend.append(String(token)); continue }
            if token.allSatisfy({ $0.isASCII && $0.isLetter }) || token == "/" { continue }
            if token == "+" { joiner = !glyphs.isEmpty; continue }
            if joiner { glyphs.append("+") }
            joiner = false
            glyphs.append(String(token))
        }
        guard !glyphs.isEmpty else { return legend.isEmpty || showKeys ? label : "" }
        guard showKeys, !legend.isEmpty else { return glyphs.joined(separator: " ") }
        return glyphs.joined(separator: " ") + " / " + legend.joined(separator: " ")
    }

    /// A token that names a key: a modifier's mark in it, or `Esc`. `⏎` is not
    /// one — in a label it is the Return the gesture presses.
    static func isKey(_ token: Substring) -> Bool {
        token == "Esc" || token.contains { "⌘⌃⌥⇧".contains($0) }
    }

    /// Everything the bar draws for a stage, cut by `shown`.
    struct Bar: Equatable {
        var crosses: [Cross] = []
        var mouse: MouseHint?
        var keys: [String] = []
        var isEmpty: Bool { crosses.isEmpty && mouse == nil }
    }

    /// **The bar for a stage** — which variant (`trackpad`: the fingers' crosses;
    /// a crop: the mouse; else the side buttons' crosses) and, through `shown`,
    /// how much each badge says: **glyphs alone with the Logitech mouse attached,
    /// glyph + key without it** (`Stage.noMouse`). A keys-row entry that is only
    /// a key (`💬 prompt ⌃P`) is not drawn with the mouse; nor is the crop's
    /// `Esc cancel`. Pure — the Logi-mode gate and the hidden switch are `update`'s.
    static func bar(for stage: Stage) -> Bar {
        let withKeys = stage.noMouse
        let trackpad = stage.fingers || (stage.noMouse && stage.listening && !stage.held && stage.crop == nil)
        var bar = Bar()
        if trackpad {
            bar.crosses = fingerCrosses(for: stage)
            bar.keys = keys(for: stage)
        } else if let mouse = mouse(for: stage) {
            bar.mouse = MouseHint(left: shown(mouse.left, keys: withKeys), wheel: shown(mouse.wheel, keys: withKeys),
                                  right: shown(mouse.right, keys: withKeys), body: shown(mouse.body, keys: withKeys))
        } else {
            bar.crosses = crosses(for: stage)
            bar.keys = keys(for: stage)
        }
        bar.crosses = bar.crosses.map { c in
            var c = c
            c.click = c.click.map { shown($0, keys: withKeys) }
            c.up = c.up.map { shown($0, keys: withKeys) }
            c.down = c.down.map { shown($0, keys: withKeys) }
            c.left = c.left.map { shown($0, keys: withKeys) }
            c.right = c.right.map { shown($0, keys: withKeys) }
            return c
        }
        bar.keys = bar.keys.filter { withKeys || !$0.split(separator: " ").contains(where: isKey) }
            .map { shown($0, keys: withKeys) }
        return bar
    }

    /// **The trackpad's crosses, under left ⌃⌥⌘** (2026-10-20, Victor: *"I should
    /// see the same tooltips in the bottom right corner to suggest what actions I
    /// can do with one finger and two fingers … add a finger somehow to the
    /// center badge"*, then *"instead of [plain] … show dictate"*). The side
    /// buttons' crosses with the finger before the click's label (☝️ 🔼, ✌️ 🔽 —
    /// `HotkeyTap.padClick`). At rest they say what each gesture starts. Pure,
    /// like `crosses`.
    static func fingerCrosses(for s: Stage) -> [Cross] {
        var c: [Cross]
        if s.listening && !s.held {
            // The keys ride in the badges already (`crosses`, *"suggest [⌃P] in
            // the button … Put command command next to the flag"*).
            c = crosses(for: Stage(listening: true, prompting: s.prompting, filming: s.filming,
                                   kamikaze: s.kamikaze,
                                   interruptible: s.interruptible, interrupt: s.interrupt,
                                   spawn: s.spawn, quick: s.quick))
        } else {
            c = [Cross(click: "💬 prompt", up: "✨ new", down: "☠️", left: "⚡ ask", right: Self.terminal + " terminal"),
                 // ✌️ → starts nothing since 2026-11-22 (*"dictarea curată start: fără 🔽 →"*).
                 Cross(click: "🎙️ dictate ⌘⌘", up: "", down: "🔌 unbind", left: "⏎", right: "")]
        }
        c[0].corner = oneFinger
        c[1].corner = twoFingers
        return c
    }

    /// The fingers, in each cross's top-left cell (`Cross.corner`).
    static let oneFinger = "☝️"
    static let twoFingers = "✌️"

    /// A label starting with this is drawn crossed out, without it.
    static let struck = "~"
    /// **Google's four-colour G, drawn where this character stands in a label**
    /// (2026-11-11, Victor: *"să apară și iconița Google în gesturi acolo, nu doar o
    /// lupă. Așa înțeleg că ajunge în browser, în Google"*) — no emoji or font has
    /// it, so `drawBox` paints it (`drawGoogleG`). A private-use code point.
    static let google = "\u{E0A0}"

    private var panel: NSPanel?
    private var board: Board?
    private var shown = Stage()
    /// The screens as of the last `show` — read once, not on every mouse move.
    private var displays: [Display] = []
    private var placed: Spot?

    /// **Bigger glyphs in narrower boxes** (2026-11-22): with the words gone a
    /// badge is one glyph, so the box's floor fell from 68 to 38 and the room
    /// went to the glyph — 12 pt → 15 pt, the box 24 → 26 tall.
    fileprivate static let font = NSFont.systemFont(ofSize: 15, weight: .medium)
    fileprivate static let boxHeight: CGFloat = 26
    fileprivate static let minBoxWidth: CGFloat = 38
    fileprivate static let ink = NSColor.white.withAlphaComponent(0.92)
    /// The Copy icon in the bar's ink (`copyKey`), made once.
    fileprivate static let copyImage: NSImage? = NSImage(systemSymbolName: "doc.on.doc",
                                                         accessibilityDescription: "Copy")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .medium)
            .applying(.init(paletteColors: [ink])))
    /// The drawn selection (`selectKey`), made once.
    /// The drawn terminal window (`terminal`), made once.
    fileprivate static let terminalImage = Glyphs.terminal(height: (font.pointSize * 1.15).rounded(), ink: ink)
    fileprivate static let selectImage = Glyphs.select(height: (font.pointSize * 1.25).rounded(), ink: ink)

    /// **The pictures a label can carry**: the size of what is painted where a
    /// private-use character stands (`google`, `copyKey`, `selectKey`), nil for
    /// a character the font draws.
    fileprivate static func pictureSize(_ c: Character) -> NSSize? {
        switch String(c) {
        case google: let g = font.capHeight + 4; return NSSize(width: g, height: g)
        case copyKey: return copyImage?.size
        case selectKey: return selectImage.size
        case terminal: return terminalImage.size
        default: return nil
        }
    }

    /// A label as runs of text and pictures, each with its width.
    fileprivate static func runs(_ text: String) -> [(text: String, picture: Character?, width: CGFloat)] {
        var out: [(text: String, picture: Character?, width: CGFloat)] = []
        var plain = ""
        func flush() {
            guard !plain.isEmpty else { return }
            out.append((plain, nil, (plain as NSString).size(withAttributes: [.font: font]).width))
            plain = ""
        }
        for c in text {
            if let size = pictureSize(c) { flush(); out.append(("", c, size.width)) } else { plain.append(c) }
        }
        flush()
        return out
    }

    /// A label's drawn width — off its runs, since the font cannot answer for a picture.
    static func labelWidth(_ label: String) -> CGFloat {
        let text = label.hasPrefix(struck) ? String(label.dropFirst(struck.count)) : label
        return runs(text).reduce(0) { $0 + $1.width }
    }
    fileprivate static let padding: CGFloat = 6
    fileprivate static let gap: CGFloat = 4
    /// Between the 🔼 cross and the 🔽 one: a row's worth, as in the sketch —
    /// widened 2026-09-30 so the two read as two buttons.
    fileprivate static let crossGap: CGFloat = 24
    /// The Retina alone: see-through (2026-09-30, Victor: *"should be semi-transparent"*),
    /// it sits over whatever he is working on in that corner.
    static let aloneOpacity: CGFloat = 0.6
    /// Across the seam nothing he reads is under it: solid (2026-10-01).
    static let acrossOpacity: CGFloat = 1
    /// Fled back to the Retina, over his work: nearly gone (2026-10-01).
    static let fledOpacity: CGFloat = 0.3
    static let margin: CGFloat = 16
    /// **The pointer this close to a bar with nowhere to flee hides it**
    /// (2026-10-08, Victor: *"when the mouse goes towards the area where the
    /// tooltips are on a single monitor setup, those should disappear when my
    /// mouse gets there because they get in the way"*). It fades back once the
    /// pointer is this far away again.
    static let dodge: CGFloat = 80
    /// How much bigger the bar is drawn on a screen that is not the Retina.
    static let offRetinaScale: CGFloat = 3

    /// **A hidden switch takes the bar off the screen** (2026-11-22, for the
    /// teaser's footage — Victor: *"nu arăta hint-urile astea din colț"*, they
    /// confuse a first-time viewer): `defaults write ro.victorrentea.wispr-relay
    /// hintBarHidden -bool true`, or `WT_HINT_BAR=0`. Off unless set; no menu row.
    /// Read at every update, so it needs no relaunch.
    static func hidden(defaults: UserDefaults = .standard,
                       environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["WT_HINT_BAR"] == "0" || defaults.bool(forKey: "hintBarHidden")
    }

    func update(_ stage: Stage) {
        // The trackpad's crosses need no Options+ profile, so no Logi gate.
        let trackpad = stage.fingers || (stage.noMouse && stage.listening && !stage.held && stage.crop == nil)
        let visible = !Self.hidden() && (trackpad || (stage.listening && !stage.held && GestureGuide.logiGesturesOn))
        guard stage != shown || (panel != nil) != visible else { return }
        shown = stage
        guard visible else { hide(); return }
        // Glyphs alone with the mouse, glyph + key without it (2026-11-22, `bar`).
        let bar = Self.bar(for: stage)
        show(bar.crosses, mouse: bar.mouse, keys: bar.keys)
    }

    /// Every mouse move, from the chip's own monitors: the bar leaves the screen
    /// the pointer is on (2026-10-01).
    func pointerMoved(_ pointer: NSPoint) {
        guard let board, !board.crosses.isEmpty || board.mouse != nil else { return }
        place(board.crosses, mouse: board.mouse, keys: board.keys, pointer: pointer)
    }

    private func show(_ crosses: [Cross], mouse: MouseHint? = nil, keys: [String] = []) {
        displays = NSScreen.screens.map { s -> Display in
            let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return Display(frame: s.frame, visible: s.visibleFrame,
                           builtIn: id.map { CGDisplayIsBuiltin($0) != 0 } ?? false)
        }
        if let board {
            board.crosses = crosses
            board.mouse = mouse
            board.keys = keys
            placed = nil
            place(crosses, mouse: mouse, keys: keys, pointer: NSEvent.mouseLocation)
            return
        }
        guard let spot = Self.spot(base: Board.size(for: crosses, mouse: mouse, keys: keys), on: displays,
                                   pointer: NSEvent.mouseLocation) else { return }
        Log.info("⌨️ hint bar ×\(Int(spot.scale)) α\(spot.opacity): \(crosses.map(Self.describe).joined(separator: " / "))")
        let p = NSPanel(contentRect: spot.rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = .none

        let b = Board(frame: NSRect(origin: .zero, size: spot.rect.size))
        b.scale = spot.scale
        b.opacity = spot.opacity > 0 ? spot.opacity : Self.aloneOpacity
        b.crosses = crosses
        b.mouse = mouse
        b.keys = keys
        b.autoresizingMask = [.width, .height]
        p.contentView = b
        p.alphaValue = 0
        p.orderFrontRegardless()
        if spot.opacity > 0 {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 1 }
        }
        panel = p
        board = b
        placed = spot
    }

    private func place(_ crosses: [Cross], mouse: MouseHint? = nil, keys: [String] = [], pointer: NSPoint) {
        guard let panel, let board,
              let spot = Self.spot(base: Board.size(for: crosses, mouse: mouse, keys: keys), on: displays,
                                   pointer: pointer),
              spot != placed else { return }
        let dodged = spot.opacity == 0, wasDodged = placed?.opacity == 0, first = placed == nil
        if placed == nil {
            Log.info("⌨️ hint bar ×\(Int(spot.scale)) α\(spot.opacity): \(crosses.map(Self.describe).joined(separator: " / "))")
        } else if dodged != wasDodged, placed?.rect == spot.rect {
            Log.info(dodged ? "⌨️ hint bar hides from the pointer" : "⌨️ hint bar back")
        } else {
            Log.info("⌨️ hint bar moved ×\(Int(spot.scale)) α\(spot.opacity)")
        }
        placed = spot
        board.scale = spot.scale
        // A dodge is the panel fading, not the drawing: the board keeps its
        // opacity for the moment the pointer leaves.
        if !dodged { board.opacity = spot.opacity }
        panel.setFrame(spot.rect, display: true)
        if dodged != wasDodged || first {
            NSAnimationContext.runAnimationGroup { $0.duration = dodged ? 0.15 : 0.3; panel.animator().alphaValue = dodged ? 0 : 1 }
        }
    }

    private func hide() {
        guard let p = panel else { return }
        panel = nil
        board = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                            completionHandler: { p.orderOut(nil) })
    }

    /// **The bar for a stage as a PNG, for the states page** (`OverlayStates`,
    /// `shape: "bar"`): solid, as across the seam, at twice its Retina size and
    /// 2× the pixels (`RelayWindow.snapshot`'s rule). Answers the size in points,
    /// nil when the stage has no bar.
    @discardableResult
    static func writeStill(of stage: Stage, to path: String, scale: CGFloat = 2) -> NSSize? {
        let bar = bar(for: stage)
        guard !bar.isEmpty else { return nil }
        let base = Board.size(for: bar.crosses, mouse: bar.mouse, keys: bar.keys)
        let size = NSSize(width: base.width * scale, height: base.height * scale)
        let board = Board(frame: NSRect(origin: .zero, size: size))
        board.crosses = bar.crosses
        board.mouse = bar.mouse
        board.keys = bar.keys
        board.scale = scale
        board.opacity = acrossOpacity
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        board.cacheDisplay(in: board.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: URL(fileURLWithPath: path))
        return size
    }

    // MARK: the README's sheets (2026-11-22)

    /// One bar on a sheet: the situation it belongs to, said above it.
    struct SheetColumn {
        var title: String
        var stage: Stage
        var light = false
    }

    /// **The bars side by side, each under its situation's name** (2026-11-22,
    /// Victor: *"pune pe fiecare coloană un titlu ce reprezintă … și imaginea
    /// asta să fie generată și pusă și în README.md pe GitHub mereu"*). Written by
    /// every states-page shoot (`OverlayStates.finish` → `writeSheets`), copied to
    /// `docs/readme/` by `build-readme-shots.py`; `sheetSpec` beside them is what
    /// `GestureHintBarTests` holds the committed pictures to.
    static let sheets: [(name: String, columns: [SheetColumn])] = [
        ("hint-bar", [
            .init(title: "Prompt", stage: .init(listening: true, prompting: true)),
            .init(title: "Prompt (light backdrop)", stage: .init(listening: true, prompting: true), light: true),
            .init(title: "Plain dictation", stage: .init(listening: true, prompting: false)),
            .init(title: "⚡ Question", stage: .init(listening: true, prompting: false, quick: true)),
            .init(title: "Filming, kamikaze on, to a new session",
                  stage: .init(listening: true, prompting: true, filming: true, kamikaze: true, spawn: true)),
        ]),
        ("hint-bar-keyboard", [
            .init(title: "No mouse: prompt", stage: .init(listening: true, prompting: true, noMouse: true)),
            .init(title: "No mouse: prompt (light backdrop)",
                  stage: .init(listening: true, prompting: true, noMouse: true), light: true),
            .init(title: "No mouse: plain dictation", stage: .init(listening: true, prompting: false, noMouse: true)),
            .init(title: "No mouse: ⚡ question",
                  stage: .init(listening: true, prompting: false, quick: true, noMouse: true)),
            .init(title: "No mouse: trackpad at rest, left ⌃⌥⌘ held", stage: .init(fingers: true, noMouse: true)),
        ]),
        ("hint-bar-crop", [
            .init(title: "Crop: drag", stage: .init(listening: true, prompting: true, crop: .selecting)),
            .init(title: "Crop: drag (light backdrop)",
                  stage: .init(listening: true, prompting: true, crop: .selecting), light: true),
            .init(title: "Crop: locked", stage: .init(listening: true, prompting: true, crop: .locked)),
            .init(title: "Crop: parked", stage: .init(listening: true, prompting: true, crop: .parked)),
            .init(title: "No mouse: crop, drag", stage: .init(listening: true, prompting: true, crop: .selecting, noMouse: true)),
        ]),
    ]

    /// What the sheets show, as text: every column's title and badges, plus the
    /// numbers the drawing is sized by. A change to any of them changes this —
    /// and the committed `docs/readme/hint-bar.txt` then fails the test until
    /// `./docs/shoot-overlay-states.sh` has drawn the pictures again.
    static func sheetSpec() -> String {
        var lines = ["font \(font.pointSize) box \(boxHeight)×\(minBoxWidth) sheet ×\(sheetScale)"]
        for sheet in sheets {
            lines.append("# \(sheet.name).png")
            for column in sheet.columns {
                let bar = bar(for: column.stage)
                var parts = bar.crosses.map { "[" + ($0.corner.map { $0 + " " } ?? "") + describe($0) + "]" }
                if let m = bar.mouse { parts.append("mouse[\(m.left)|\(m.wheel)|\(m.right)|\(m.body)]") }
                if !bar.keys.isEmpty { parts.append("keys[" + bar.keys.joined(separator: "|") + "]") }
                lines.append("\(column.title)\(column.light ? " ☀" : ""): " + parts.joined(separator: " "))
            }
        }
        // The drawn glyphs by name — a private-use character prints as nothing.
        return [(google, "‹G›"), (copyKey, "‹copy›"), (selectKey, "‹select›"), (terminal, "‹terminal›")]
            .reduce(lines.joined(separator: "\n") + "\n") { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    static let sheetSpecName = "hint-bar.txt"
    /// The sheets draw each bar at this many times its Retina size.
    static let sheetScale: CGFloat = 2

    /// Every sheet as `<dir>/<name>.png`, and `sheetSpec` beside them.
    static func writeSheets(into dir: String) {
        for sheet in sheets {
            let view = SheetView(columns: sheet.columns)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
                                             pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(sheet.name + ".png"))
        }
        try? sheetSpec().write(toFile: (dir as NSString).appendingPathComponent(sheetSpecName),
                               atomically: true, encoding: .utf8)
    }

    /// A sheet: one panel per column — the title, then the bar, solid as across
    /// the seam, on a dark desktop or a light one.
    private final class SheetView: NSView {
        private var panels: [(rect: NSRect, column: SheetColumn)] = []
        private static let pad: CGFloat = 28, gap: CGFloat = 14, titleHeight: CGFloat = 52, minPanel: CGFloat = 250
        private static let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)

        override var isFlipped: Bool { true }

        init(columns: [SheetColumn]) {
            super.init(frame: .zero)
            let k = GestureHintBar.sheetScale
            let bars = columns.map { column -> (Bar, NSSize) in
                let bar = GestureHintBar.bar(for: column.stage)
                let base = Board.size(for: bar.crosses, mouse: bar.mouse, keys: bar.keys)
                return (bar, NSSize(width: base.width * k, height: base.height * k))
            }
            let tallest = bars.map(\.1.height).max() ?? 0
            let height = Self.titleHeight + tallest + Self.pad * 2
            var x: CGFloat = 0
            for (column, (bar, size)) in zip(columns, bars) {
                let width = max(Self.minPanel, size.width + Self.pad * 2)
                let panel = NSRect(x: x, y: 0, width: width, height: height)
                panels.append((panel, column))
                let board = Board(frame: NSRect(x: panel.midX - size.width / 2, y: Self.titleHeight + Self.pad,
                                                width: size.width, height: size.height))
                board.crosses = bar.crosses
                board.mouse = bar.mouse
                board.keys = bar.keys
                board.scale = k
                board.opacity = GestureHintBar.acrossOpacity
                addSubview(board)
                x += width + Self.gap
            }
            frame = NSRect(x: 0, y: 0, width: x - Self.gap, height: height)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byWordWrapping
            for (rect, column) in panels {
                NSColor(white: column.light ? 0.93 : 0.12, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
                let title = NSAttributedString(string: column.title, attributes: [
                    .font: Self.titleFont, .paragraphStyle: style,
                    .foregroundColor: NSColor(white: column.light ? 0.1 : 0.95, alpha: 1),
                ])
                let box = NSRect(x: rect.minX + 10, y: 0, width: rect.width - 20, height: Self.titleHeight + Self.pad)
                let needed = title.boundingRect(with: box.size, options: [.usesLineFragmentOrigin]).height
                title.draw(with: NSRect(x: box.minX, y: box.midY - needed / 2, width: box.width, height: needed),
                           options: [.usesLineFragmentOrigin])
            }
        }
    }

    private static func describe(_ c: Cross) -> String {
        [("·", c.click), ("↑", c.up), ("↓", c.down), ("←", c.left), ("→", c.right)]
            .compactMap { k, v in v.flatMap { $0.isEmpty ? nil : "\(k) \($0)" } }
            .joined(separator: ", ")
    }

    /// A screen as `placement` needs it — plain values, so it is tested without one.
    struct Display: Equatable {
        var frame: NSRect
        var visible: NSRect
        var builtIn: Bool
    }

    /// Where the bar is drawn, how big and how solid.
    struct Spot: Equatable {
        var rect: NSRect
        var scale: CGFloat
        var opacity: CGFloat
    }

    /// The bar for a pointer. Across the seam it is `offRetinaScale` and solid;
    /// with the pointer on that same screen it flees to the Retina's side of the
    /// seam, at its small size and `fledOpacity`. The Retina alone, or the lid
    /// closed, has nowhere to flee to: it stays put.
    static func spot(base: NSSize, on screens: [Display], pointer: NSPoint) -> Spot? {
        let big = NSSize(width: base.width * offRetinaScale, height: base.height * offRetinaScale)
        guard let home = screens.first(where: \.builtIn),
              screens.contains(where: { !$0.builtIn }) else {
            let scale = scale(on: screens)
            let size = NSSize(width: base.width * scale, height: base.height * scale)
            return placement(size: size, on: screens).map {
                let near = NSMouseInRect(pointer, $0.insetBy(dx: -dodge, dy: -dodge), false)
                return Spot(rect: $0, scale: scale, opacity: near ? 0 : scale == 1 ? aloneOpacity : acrossOpacity)
            }
        }
        guard let (across, seam) = host(on: screens),
              let rect = placement(size: big, on: screens) else { return nil }
        guard NSMouseInRect(pointer, across.frame, false) else {
            return Spot(rect: rect, scale: offRetinaScale, opacity: acrossOpacity)
        }
        let v = home.visible, m = margin
        let w = base.width, h = base.height
        let y = max(v.minY, across.visible.minY) + m
        let x = min(v.maxX, across.visible.maxX) - w - m
        let fled: NSRect
        switch seam {
        case .right: fled = NSRect(x: v.maxX - w - m, y: y, width: w, height: h)
        case .left: fled = NSRect(x: v.minX + m, y: y, width: w, height: h)
        case .below: fled = NSRect(x: x, y: v.minY + m, width: w, height: h)
        case .above: fled = NSRect(x: x, y: v.maxY - h - m, width: w, height: h)
        case .none: fled = NSRect(x: v.maxX - w - m, y: v.minY + m, width: w, height: h)
        }
        return Spot(rect: fled, scale: 1, opacity: fledOpacity)
    }

    /// `placement` puts the bar on the Retina only when it is the sole screen;
    /// anywhere else (a secondary, or the lid closed) it is drawn `offRetinaScale`.
    static func scale(on screens: [Display]) -> CGFloat {
        screens.contains { !$0.builtIn } ? offRetinaScale : 1
    }

    /// Which side of the Retina the secondary that holds the bar touches.
    enum Seam { case right, left, below, above, none }

    /// The secondary the bar goes on — the one right of the Retina first, then
    /// any touching it, then any — and the Retina's edge it shares. Nil without
    /// a Retina or without a secondary.
    static func host(on screens: [Display]) -> (Display, Seam)? {
        guard let home = screens.first(where: \.builtIn) else { return nil }
        let others = screens.filter { !$0.builtIn }
        let r = home.frame, slack: CGFloat = 2
        func overlapsV(_ f: NSRect) -> Bool { f.minY < r.maxY && f.maxY > r.minY }
        func overlapsH(_ f: NSRect) -> Bool { f.minX < r.maxX && f.maxX > r.minX }
        if let s = others.first(where: { abs($0.frame.minX - r.maxX) <= slack && overlapsV($0.frame) }) {
            return (s, .right)
        }
        if let s = others.first(where: { abs($0.frame.maxX - r.minX) <= slack && overlapsV($0.frame) }) {
            return (s, .left)
        }
        if let s = others.first(where: { abs($0.frame.maxY - r.minY) <= slack && overlapsH($0.frame) }) {
            return (s, .below)
        }
        if let s = others.first(where: { abs($0.frame.minY - r.maxY) <= slack && overlapsH($0.frame) }) {
            return (s, .above)
        }
        return others.first.map { ($0, .none) }
    }

    /// Where the bar goes. The Retina alone (or no Retina at all, lid closed):
    /// its bottom-right corner, as before. Otherwise the `host` secondary,
    /// against the edge it shares with the Retina, at the bottom (left/right
    /// seam) or the right end (top/bottom seam).
    static func placement(size: NSSize, on screens: [Display]) -> NSRect? {
        let m = margin
        func corner(_ v: NSRect) -> NSRect {
            NSRect(x: v.maxX - size.width - m, y: v.minY + m, width: size.width, height: size.height)
        }
        guard let home = screens.first(where: \.builtIn) else {
            return screens.first.map { corner($0.visible) }
        }
        guard let (s, seam) = host(on: screens) else { return corner(home.visible) }
        let r = home.frame, v = s.visible
        // The part of the seam both screens own, so the bar stays by the Retina.
        let seamY = max(v.minY, r.minY) + m
        let seamX = min(v.maxX, r.maxX) - size.width - m
        switch seam {
        case .right: return NSRect(x: v.minX + m, y: seamY, width: size.width, height: size.height)
        case .left: return NSRect(x: v.maxX - size.width - m, y: seamY, width: size.width, height: size.height)
        case .below: return NSRect(x: seamX, y: v.maxY - size.height - m, width: size.width, height: size.height)
        case .above: return NSRect(x: seamX, y: v.minY + m, width: size.width, height: size.height)
        case .none: return corner(v)
        }
    }

    /// The crosses, drawn. A three-column grid shared by both, so their centre
    /// boxes line up. **Each column is as wide as its own widest badge**
    /// (2026-11-22 — every box was as wide as the bar's widest label until then,
    /// so one `⏹️ + ⏎` in the middle cost the two side columns its width too).
    final class Board: NSView {
        var crosses: [Cross] = [] { didSet { needsDisplay = true } }
        /// Set during a crop, in place of the crosses.
        var mouse: MouseHint? { didSet { needsDisplay = true } }
        /// The keys row under the crosses (`GestureHintBar.keys`).
        var keys: [String] = [] { didSet { needsDisplay = true } }
        /// Drawn at `size(for:)` × this; the frame is already that big.
        var scale: CGFloat = 1 { didSet { needsDisplay = true } }
        /// The whole board's alpha; at 1 the boxes are solid too ("fully opaque").
        var opacity: CGFloat = GestureHintBar.aloneOpacity { didSet { needsDisplay = true } }

        override var isFlipped: Bool { true }

        /// The three columns' widths: ← | click ↑ ↓ | →, each key in the column
        /// `keyColumn` puts it in.
        static func columnWidths(for crosses: [Cross], keys: [String] = []) -> [CGFloat] {
            var labels: [[String?]] = [crosses.map(\.left), crosses.flatMap { [$0.click, $0.up, $0.down] },
                                       crosses.map(\.right)]
            for (i, key) in keys.enumerated() { labels[keyColumn(i, of: keys.count)].append(key) }
            return labels.map { column in
                let widest = column.compactMap { $0 }.map(GestureHintBar.labelWidth).max() ?? 0
                return max(GestureHintBar.minBoxWidth, ceil(widest) + GestureHintBar.padding * 2)
            }
        }

        /// Three keys to a line, each line right-aligned.
        static func keyColumn(_ i: Int, of count: Int) -> Int {
            let line = i / 3, inLine = min(3, count - line * 3)
            return 3 - inLine + i % 3
        }

        static func mouseBoxWidth(for m: MouseHint) -> CGFloat {
            let widest = [m.left, m.wheel, m.right].map(GestureHintBar.labelWidth).max() ?? 0
            return max(GestureHintBar.minBoxWidth, ceil(widest) + GestureHintBar.padding * 2)
        }

        /// The mouse: three buttons side by side, as tall as two boxes, over a
        /// body as tall as two more.
        static func size(for crosses: [Cross], mouse: MouseHint?, keys: [String] = []) -> NSSize {
            guard let mouse else { return size(for: crosses, keys: keys) }
            let h = GestureHintBar.boxHeight, gap = GestureHintBar.gap
            return NSSize(width: mouseBoxWidth(for: mouse) * 3 + gap * 2, height: h * 4 + gap)
        }

        static func size(for crosses: [Cross], keys: [String] = []) -> NSSize {
            let crossHeight = GestureHintBar.boxHeight * 3 + GestureHintBar.gap * 2
            let n = CGFloat(crosses.count)
            return NSSize(width: columnWidths(for: crosses, keys: keys).reduce(0, +) + GestureHintBar.gap * 2,
                          height: crossHeight * n + GestureHintBar.crossGap * max(0, n - 1)
                                + keysHeight(keys.count))
        }

        /// The keys row: a third of a cross gap above it, three boxes to a line.
        static func keysHeight(_ n: Int) -> CGFloat {
            guard n > 0 else { return 0 }
            let lines = CGFloat((n + 2) / 3)
            return GestureHintBar.crossGap / 2 + lines * GestureHintBar.boxHeight
                + (lines - 1) * GestureHintBar.gap
        }

        override func draw(_ dirtyRect: NSRect) {
            let widths = Self.columnWidths(for: crosses, keys: keys)
            let h = GestureHintBar.boxHeight, gap = GestureHintBar.gap
            func x(_ col: Int) -> CGFloat { widths[..<col].reduce(0, +) + CGFloat(col) * gap }
            let crossHeight = h * 3 + gap * 2
            let cg = NSGraphicsContext.current?.cgContext
            cg?.scaleBy(x: scale, y: scale)
            cg?.setAlpha(opacity)
            cg?.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { cg?.endTransparencyLayer() }
            if let mouse {
                drawMouse(mouse)
                return
            }
            for (i, c) in crosses.enumerated() {
                let top = CGFloat(i) * (crossHeight + GestureHintBar.crossGap)
                func box(_ text: String?, col: Int, row: Int) {
                    guard let text else { return }
                    let r = NSRect(x: x(col), y: top + CGFloat(row) * (h + gap), width: widths[col], height: h)
                    drawBox(text, in: r)
                }
                box(c.up, col: 1, row: 0)
                box(c.left, col: 0, row: 1)
                box(c.click, col: 1, row: 1)
                box(c.right, col: 2, row: 1)
                box(c.down, col: 1, row: 2)
                if let corner = c.corner {
                    // The top-left cell alone, clear of the ← box under it.
                    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: h * 0.8)]
                    let size = (corner as NSString).size(withAttributes: attrs)
                    (corner as NSString).draw(at: NSPoint(x: (widths[0] - size.width) / 2, y: top + (h - size.height) / 2),
                                              withAttributes: attrs)
                }
            }
            // The keys, right-aligned under the 🔽 cross — the column the eye
            // ends on — in the crosses' own boxes.
            let n = CGFloat(crosses.count)
            let keysTop = crossHeight * n + GestureHintBar.crossGap * max(0, n - 1) + GestureHintBar.crossGap / 2
            for (i, key) in keys.enumerated() {
                let line = i / 3, col = Self.keyColumn(i, of: keys.count)
                drawBox(key, in: NSRect(x: x(col), y: keysTop + CGFloat(line) * (h + gap),
                                        width: widths[col], height: h))
            }
        }

        /// Left, wheel and right across the top — the outer two rounded at their
        /// outer top corner so the row reads as a mouse — and the body under
        /// them, rounded at the bottom.
        private func drawMouse(_ m: MouseHint) {
            let w = Self.mouseBoxWidth(for: m)
            let h = GestureHintBar.boxHeight, gap = GestureHintBar.gap
            let buttonHeight = h * 2
            let big = buttonHeight * 0.6
            func button(_ label: String, col: Int, topLeft: CGFloat, topRight: CGFloat) {
                let r = NSRect(x: CGFloat(col) * (w + gap), y: 0, width: w, height: buttonHeight)
                drawBox(label, in: r, path: Self.roundedPath(r.insetBy(dx: 0.5, dy: 0.5),
                                                              topLeft: topLeft, topRight: topRight,
                                                              bottomLeft: 4, bottomRight: 4))
            }
            button(m.left, col: 0, topLeft: big, topRight: 4)
            button(m.wheel, col: 1, topLeft: 4, topRight: 4)
            button(m.right, col: 2, topLeft: 4, topRight: big)
            let body = NSRect(x: 0, y: buttonHeight + gap, width: w * 3 + gap * 2, height: h * 2 - gap)
            drawBox(m.body, in: body, path: Self.roundedPath(body.insetBy(dx: 0.5, dy: 0.5),
                                                              topLeft: 4, topRight: 4,
                                                              bottomLeft: big, bottomRight: big))
        }

        /// A rectangle with its own radius per corner, in this flipped view.
        static func roundedPath(_ r: NSRect, topLeft: CGFloat, topRight: CGFloat,
                                bottomLeft: CGFloat, bottomRight: CGFloat) -> NSBezierPath {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + topLeft, y: r.minY))
            p.line(to: NSPoint(x: r.maxX - topRight, y: r.minY))
            p.appendArc(withCenter: NSPoint(x: r.maxX - topRight, y: r.minY + topRight), radius: topRight,
                        startAngle: 270, endAngle: 360)
            p.line(to: NSPoint(x: r.maxX, y: r.maxY - bottomRight))
            p.appendArc(withCenter: NSPoint(x: r.maxX - bottomRight, y: r.maxY - bottomRight), radius: bottomRight,
                        startAngle: 0, endAngle: 90)
            p.line(to: NSPoint(x: r.minX + bottomLeft, y: r.maxY))
            p.appendArc(withCenter: NSPoint(x: r.minX + bottomLeft, y: r.maxY - bottomLeft), radius: bottomLeft,
                        startAngle: 90, endAngle: 180)
            p.line(to: NSPoint(x: r.minX, y: r.minY + topLeft))
            p.appendArc(withCenter: NSPoint(x: r.minX + topLeft, y: r.minY + topLeft), radius: topLeft,
                        startAngle: 180, endAngle: 270)
            p.close()
            return p
        }

        /// Google's G: a ring in four arcs — red over the top, yellow on the left,
        /// green along the bottom, blue up the right and into the bar — with the
        /// mouth open on the upper right.
        static func drawGoogleG(in r: NSRect) {
            let c = NSPoint(x: r.midX, y: r.midY)
            // The bar's view is flipped: the angles below are drawn y-up.
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let up = NSAffineTransform()
            up.translateX(by: 0, yBy: c.y * 2)
            up.scaleX(by: 1, yBy: -1)
            up.concat()
            let t = r.width * 0.22
            let radius = r.width / 2 - t / 2
            func arc(_ from: CGFloat, _ to: CGFloat, _ hex: UInt32) {
                let p = NSBezierPath()
                p.appendArc(withCenter: c, radius: radius, startAngle: from, endAngle: to)
                p.lineWidth = t
                p.lineCapStyle = .butt
                color(hex).setStroke()
                p.stroke()
            }
            func color(_ hex: UInt32) -> NSColor {
                NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
            arc(42, 145, 0xEA4335)    // red
            arc(145, 215, 0xFBBC05)   // yellow
            arc(215, 322, 0x34A853)   // green
            arc(322, 360, 0x4285F4)   // blue, the right side under the mouth
            color(0x4285F4).setFill()
            NSRect(x: c.x - t * 0.15, y: c.y - t / 2, width: r.maxX - (c.x - t * 0.15), height: t).fill()
        }

        private func drawBox(_ label: String, in r: NSRect, path given: NSBezierPath? = nil) {
            let struck = label.hasPrefix(GestureHintBar.struck)
            let text = struck ? String(label.dropFirst(GestureHintBar.struck.count)) : label
            let empty = text.isEmpty
            let path = given ?? NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            // An unused gesture is a plain gray box (2026-09-30, Victor: *"place
            // gray boxes on all unused gestures"*) — seen, and plainly not a label.
            let solid = opacity >= 1
            (empty ? NSColor(white: 0.5, alpha: solid ? 1 : 0.55)
                   : NSColor.black.withAlphaComponent(solid ? 1 : 0.66)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(empty ? 0.3 : 0.45).setStroke()
            path.lineWidth = 1
            path.stroke()
            guard !empty else { return }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byClipping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: GestureHintBar.font,
                .foregroundColor: GestureHintBar.ink,
                .paragraphStyle: style,
            ]
            let s = text as NSString
            var ts = s.size(withAttributes: attrs)
            let runs = GestureHintBar.runs(text)
            if runs.contains(where: { $0.picture != nil }) {
                // Each picture in its own box (Google's G, the Copy icon, the
                // selection), the words around it drawn left-aligned from where
                // the centred whole would start.
                let left: [NSAttributedString.Key: Any] = attrs.filter { $0.key != .paragraphStyle }
                ts.width = runs.reduce(0) { $0 + $1.width }
                var x = max(r.minX + 4, r.midX - ts.width / 2)
                for run in runs {
                    if let c = run.picture, let size = GestureHintBar.pictureSize(c) {
                        let box = NSRect(x: x, y: r.midY - size.height / 2, width: size.width, height: size.height)
                        switch String(c) {
                        case GestureHintBar.google: Self.drawGoogleG(in: box)
                        case GestureHintBar.copyKey:
                            GestureHintBar.copyImage?.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                                                           respectFlipped: true, hints: nil)
                        case GestureHintBar.terminal:
                            GestureHintBar.terminalImage.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                                                              respectFlipped: true, hints: nil)
                        default:
                            GestureHintBar.selectImage.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                                                            respectFlipped: true, hints: nil)
                        }
                    } else {
                        (run.text as NSString).draw(at: NSPoint(x: x, y: r.midY - ts.height / 2), withAttributes: left)
                    }
                    x += run.width
                }
            } else {
                s.draw(in: NSRect(x: r.minX + 4, y: r.midY - ts.height / 2, width: r.width - 8, height: ts.height),
                       withAttributes: attrs)
            }
            guard struck else { return }
            let half = min(ts.width, r.width - 8) / 2 + 3
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: r.midX - half, y: r.maxY - 3))
            slash.line(to: NSPoint(x: r.midX + half, y: r.minY + 3))
            slash.lineWidth = 2.5
            slash.lineCapStyle = .round
            NSColor.systemRed.setStroke()
            slash.stroke()
        }
    }
}
