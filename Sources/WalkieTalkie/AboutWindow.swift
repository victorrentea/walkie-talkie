import AppKit

/// **What this app is, where its code lives, and what every button of the mouse
/// does — as a window this app draws, not a page it writes to disk.**
///
/// The one fact about the relay that is nowhere on the machine it runs on: it is
/// installed as a bundle in `/Applications`, launched at login, and has no
/// window of its own — so somebody looking at the walkie-talkie in the menu bar
/// and wondering what it is, or wanting to read the source, has nothing to
/// follow.
///
/// ## It was an HTML page in the browser until 2026-09-22
///
/// `AboutPage` rendered a string, wrote it to
/// `~/Library/Caches/…/about.html` and handed it to `NSWorkspace`. The reason
/// was real and is worth writing down because it is *not* the reason this
/// changed: the app never activates itself — `.regular` since 2026-09-07 for the
/// Dock tile, but nothing calls `NSApp.activate` and the overlay is a
/// `.nonactivatingPanel` — so a modal it puts up arrives behind whatever is in
/// front and steals focus from the terminal Victor is bound to.
///
/// **That argument is against an `NSAlert`, not against a window.** A
/// `.nonactivatingPanel` is exactly the thing the overlay already is: it comes
/// up in front, it takes no focus, and the terminal underneath keeps the caret.
/// Victor asked for it directly — *"să fie nu webpage ci pagina swift de
/// about"* — and the browser route was costing three things:
///
/// | the page paid | the window does not |
/// |---|---|
/// | **every drawing twice, as base64 PNG** — one per palette, baked at render time and chosen by CSS | draws once, in `MouseView.draw(_:)`, from the palette **that view** is in — see there, the colours still have to be explicit and the reason is the same one |
/// | a **file in Caches** the system may purge, and a stylesheet duplicating what AppKit already knows about type, spacing and the accent colour | nothing on disk |
/// | **leaving the app** to read about the app, in whatever Chrome window happened to be frontmost | a panel beside the menu it came from |
///
/// **The mouse is drawn because the menu cannot draw it.** A menu row gets one
/// line of text; his mouse takes a picture, and the picture is the one rendering
/// in which *which button* needs no legend of its own.
///
/// **One picture, and every button is on it** (2026-09-22). This went through
/// two shapes in an evening and the second one is the lesson. First it was two
/// drawings — `Glyphs.mouse` from over the desk for the deck and the wheel,
/// `Glyphs.mouseSide` along the flank for the thumb buttons — each card
/// illustrated by whichever view could see its subject. It worked, and Victor
/// threw it out on sight: *"1 singură poză, din diagonală cumva să se vadă
/// toate butoanele."*
///
/// He is right, and the reason is worth keeping: two views is not a drawing, it
/// is **a drawing plus an instruction to assemble one mouse out of two
/// pictures**, and that assembly is exactly the work the picture was there to
/// save. `Glyphs.mouseIso` — the three-quarter, traced off Logitech's own
/// product render — has all five buttons in one frame, so a card is a card
/// again and there is no rule about which view to use.
enum AboutWindow {

    static let repository = "https://github.com/victorrentea/walkie-talkie"

    /// When the running binary was built — the same stamp the menu row carries,
    /// so the panel and the row cannot disagree about which build this is.
    static var buildStamp: String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date ?? Date())
    }

    /// **The rows are handed over by `StatusItem`, never copied into this file.**
    /// The menu is where the gestures are written down — that is the whole design
    /// of `gestureRows` — and a second table here would be a second truth, drifting
    /// the first time a chord moves. `StatusItem` publishes its table as it builds
    /// it, so the panel renders whatever the menu is showing at that moment.
    struct Gesture {
        let label: String
        /// The legend as the menu draws it while *Mouse Gestures: Logi* is ticked.
        let logi: String
        /// The legend for the wheel vocabulary it replaced.
        let wheel: String
        let logiGlyph: String
        let wheelGlyph: String
    }
    static var gestures: [Gesture] = []
    /// Which of the two vocabularies is live, so the panel can say so rather than
    /// make the reader guess which half of the table is about the mouse in his hand.
    static var logiGesturesOn = true

    // MARK: - The window

    /// **One panel, rebuilt on every open.** The gesture table is pushed in by
    /// `StatusItem` immediately before the open and the build stamp is read off
    /// the executable, so a panel left up from an earlier launch would be a
    /// second truth of exactly the kind the `gestures` contract exists to avoid.
    /// Rebuilding costs a few dozen views once per click.
    private static var panel: NSPanel?

    static func show() {
        panel?.close()

        // **`.nonactivatingPanel`, which is the whole reason this can be a
        // window at all.** It orders in front without making this app active,
        // so the terminal Victor is bound to keeps the caret and the keyboard.
        // `.utilityWindow` gives it the narrow title bar a reference panel wants
        // rather than a document's.
        // A placeholder rect — `setContentSize` below replaces it once the
        // stack has been measured. It is not the panel's real size.
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: tableWidth + 68, height: 720),
                        styleMask: [.titled, .closable, .resizable,
                                    .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Victor's Walkie Talkie"
        p.isFloatingPanel = true
        p.level = .floating
        // Nothing in here takes typing, so it never needs to be key — and a
        // panel that took the keyboard would undo the line above.
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: tableWidth + 52, height: 320)

        // **Everything below is frame-based on purpose, and it is a bug fix.**
        //
        // The first version wired the stack to the document view and the
        // document's width to the clip view with constraints, and let the
        // window's own `contentRect` stand. On screen the panel came up
        // **0 × 0** — present, `onscreen: true`, layer 3, alpha 1, and no size
        // at all (`CGWindowListCopyWindowInfo`, which is how it was found, since
        // nothing is wrong from inside the process). A scroll view whose
        // document's width is pinned to its own clip view gives auto layout a
        // circular width with no anchor, and the window collapsed onto it.
        //
        // **And the harness had hidden it**: the panel was being photographed by
        // forcing `documentView.frame` before `cacheDisplay`, which is exactly
        // the step that was broken — it rendered beautifully and proved nothing
        // about the window. The check that catches this is the window server's
        // own bounds, not a snapshot.
        //
        // The content has a fixed width (`tableWidth`) by construction, so
        // there is nothing for auto layout to solve here: measure the stack,
        // size the document to it, size the window to that.
        let body = NSStackView(views: content())
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 14
        body.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 24, right: 26)
        let fit = body.fittingSize
        body.setFrameOrigin(.zero)
        body.setFrameSize(fit)

        // A flipped document so the content sits at the **top** of the panel and
        // grows downward; an unflipped one hangs it off the bottom and a short
        // page floats in the middle of the window.
        let doc = FlippedView(frame: NSRect(origin: .zero, size: fit))
        doc.addSubview(body)

        let visibleHeight = min(fit.height, 780)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: fit.width, height: visibleHeight))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = doc

        p.contentView = scroll
        p.setContentSize(NSSize(width: fit.width, height: visibleHeight))
        p.center()
        // **`orderFrontRegardless`, never `makeKeyAndOrderFront`.** The second
        // one activates the app, which is the one thing this whole file is
        // arranged not to do.
        p.orderFrontRegardless()
        panel = p
        Log.info("→ about panel \(Int(p.frame.width))×\(Int(p.frame.height))")
    }

    /// **What the panel actually came up at**, for `POST /test/about`. The
    /// window server's numbers, not the layout's intent — see `onTestAbout`.
    static func describe() -> [String: Any] {
        show()
        guard let p = panel else { return ["shown": false] }
        return ["shown": true,
                "visible": p.isVisible,
                "w": Int(p.frame.width), "h": Int(p.frame.height),
                "vocabulary": vocabulary,
                "gestures": gestures.count]
    }

    /// A document view that measures from the top left, so the stack inside the
    /// scroll view fills downward like a page.
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    // MARK: - The drawing

    /// **The mouse, drawn at draw time, in the palette this view is actually
    /// in.** One drawing, `Glyphs.mouseIso`, whatever button is being named.
    ///
    /// The page rasterised every drawing **twice**, to base64 PNG, one per
    /// palette, and let CSS pick — because `NSColor`'s dynamic colours resolve
    /// against whatever appearance is current when they are rasterised, and for
    /// an image baked outside any view that is the *process's*, which on a Mac
    /// in dark mode made the "light" copy a pale grey mouse invisible on a white
    /// page. The page's own comment records that
    /// `performAsCurrentDrawingAppearance` did not fix it and that passing the
    /// two colours in did.
    ///
    /// **That is still true here, and rendering the panel proved it.** The first
    /// version of this view called `Glyphs.mouse(height:pressed:)` and let the
    /// defaults resolve; in the dark snapshot the body vanished and only the red
    /// was left. So the colours are still chosen explicitly — what changed is
    /// *what they are chosen from*: `effectiveAppearance`, this view's own,
    /// rather than the process's. One instance is then right in both themes, it
    /// follows a theme switch while the panel is open
    /// (`viewDidChangeEffectiveAppearance`), and there is one rasterisation
    /// instead of two and no base64 and no file.
    final class MouseView: NSView {
        /// Width over height of `Glyphs.mouseIso`, from the render's alpha
        /// bounding box. Hard-coded here rather than asked of `Glyphs` because
        /// the constraint has to exist before any image does.
        static let aspect: CGFloat = 1.4415
        private let pressed: Glyphs.Buttons

        init(pressed: Glyphs.Buttons, height: CGFloat) {
            self.pressed = pressed
            let aspect = Self.aspect
            super.init(frame: NSRect(x: 0, y: 0, width: (height * aspect).rounded(), height: height))
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: (height * aspect).rounded()),
                heightAnchor.constraint(equalToConstant: height),
            ])
            setAccessibilityLabel(accessibilityName)
        }
        required init?(coder: NSCoder) { nil }

        override func draw(_ dirty: NSRect) {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let body = dark ? NSColor(srgbRed: 0.90, green: 0.90, blue: 0.93, alpha: 1)
                            : NSColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1)
            let red = dark ? NSColor(srgbRed: 1.00, green: 0.31, blue: 0.27, alpha: 1)
                           : NSColor(srgbRed: 0.85, green: 0.15, blue: 0.13, alpha: 1)
            Glyphs.mouseIso(height: bounds.height, pressed: pressed, body: body, highlight: red)
                .draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        }

        /// The palette is read in `draw(_:)`, so a theme switch has to ask for
        /// one. Without this the panel keeps the mouse it was opened with.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }

        private var accessibilityName: String {
            var parts: [String] = []
            if pressed.contains(.left) { parts.append("left button") }
            if pressed.contains(.right) { parts.append("right button") }
            if pressed.contains(.wheel) { parts.append("wheel") }
            if pressed.contains(.forward) { parts.append("front side button") }
            if pressed.contains(.back) { parts.append("rear side button") }
            return parts.isEmpty ? "mouse" : "mouse, " + parts.joined(separator: " and ")
        }
    }

    private static func viewFor(_ pressed: Glyphs.Buttons, height: CGFloat) -> MouseView {
        MouseView(pressed: pressed, height: height)
    }

    // MARK: - The buttons

    /// **One button of the mouse, named the way the app names it.**
    ///
    /// `emoji` is the vocabulary the menu writes chords in — an emoji for the
    /// button, because it names it by *where it sits on the mouse* rather than
    /// by a word. That is exactly the shorthand this panel exists to decode,
    /// which is why the emoji is printed here beside the drawing.
    ///
    /// **Every string here is English**, like every other string the app
    /// renders — the panel's copy was Romanian while it was an HTML page in a
    /// browser, and moving it into an AppKit window put it under the rule in
    /// `CLAUDE.md`. `vocabulary` says `Logi` / `Wheel`, the two words the
    /// `Mouse Gestures` menu row already uses, so the panel and the row cannot
    /// come to call the same set different things.
    ///
    /// **`fallback` is only for a button no gesture uses.** What each button
    /// *does* is not written down here any more — it is read off the live
    /// gesture table, for the active vocabulary, by `actions(for:)`. A
    /// hand-written list was a second copy of `gestureRows` that described the
    /// Logi set while the menu might be on the wheel set, which is precisely
    /// the drift Victor's *"ajustat după alegerea actuală de gestures"* is
    /// about.
    private struct Button {
        let emoji: String
        let pressed: Glyphs.Buttons
        let name: String
        let fallback: String?
    }

    /// Front to back, left flank last, which is the order a hand meets them.
    private static let buttons: [Button] = [
        Button(emoji: "◀️", pressed: .left, name: "Left button", fallback: nil),
        Button(emoji: "▶️", pressed: .right, name: "Right button",
               fallback: "untouched — stays the application's"),
        Button(emoji: "🛞", pressed: .wheel, name: "Wheel", fallback: nil),
        Button(emoji: "🔼", pressed: .forward, name: "Front side button", fallback: nil),
        Button(emoji: "🔽", pressed: .back, name: "Rear side button", fallback: nil),
    ]

    /// **Everything the active vocabulary does with this button**, read off the
    /// table `StatusItem` published — so a gesture that moves, or a vocabulary
    /// that is switched, changes this list without anybody editing this file.
    ///
    /// A chord that presses two buttons appears under **both**, deliberately:
    /// `◀️ + 🔼` is a fact about the left button as much as about the forward
    /// one, and a reader looking up either of them needs to be told.
    private static func actions(for button: Glyphs.Buttons) -> [(move: String, what: String)] {
        gestures.compactMap { g in
            let c = parse(chord(of: g))
            guard c.pressed.contains(button) else { return nil }
            // The other buttons in the chord, so a two-button gesture reads as
            // one: `+ 🔼  →  Connect Terminal` under the left button.
            var prefix = ""
            for other in buttons where other.pressed != button && c.pressed.contains(other.pressed) {
                prefix += "+ \(other.emoji) "
            }
            let repeats = c.repeats > 0 ? "×\(c.repeats + 1) " : ""
            return (prefix + repeats + c.movement, g.label)
        }
    }

    /// **A row of the legend: the picture, then what that button is for.**
    ///
    /// It was a grid of five cards until the drawing became one three-quarter
    /// view. Cards worked while every button had one hand-written note; with
    /// the notes read off the live table the counts are wildly uneven — the
    /// wheel carries six gestures in the wheel vocabulary and the right button
    /// carries none — and five fixed-width cards of wildly different heights is
    /// a ragged grid. A vertical list is what a legend is anyway.
    private static func buttonRow(_ b: Button) -> NSView {
        let art = viewFor(b.pressed, height: 62)

        let title = NSStackView(views: [
            label(b.emoji, size: 15),
            label(b.name, size: 13, weight: .semibold),
        ])
        title.orientation = .horizontal
        title.alignment = .firstBaseline
        title.spacing = 6

        var rows: [NSView] = [title]
        let found = actions(for: b.pressed)
        if found.isEmpty {
            // **A button with nothing on it says which set it is idle in**, not
            // `—`. Rendering the wheel vocabulary is what asked for this: the
            // forward button carries four gestures under Logi and none under
            // Rotiță, and a bare dash there reads as *this button does nothing*
            // rather than *this button does nothing in the set you are on*.
            rows.append(label(b.fallback ?? "unused in the \(vocabulary) set",
                              size: 11, colour: .tertiaryLabelColor,
                              width: legendTextWidth, wraps: true))
        } else {
            for a in found {
                let move = label(a.move.isEmpty ? "click" : a.move,
                                 size: 12, weight: .semibold, width: 62)
                let what = label(a.what, size: 12, colour: .secondaryLabelColor,
                                 width: legendTextWidth - 70, wraps: true)
                let line = NSStackView(views: [move, what])
                line.orientation = .horizontal
                line.alignment = .firstBaseline
                line.spacing = 8
                rows.append(line)
            }
        }

        let text = NSStackView(views: rows)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [art, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        return row
    }

    // MARK: - Reading a chord

    /// **A chord, taken apart once.** `drawn` used to do this inline; the button
    /// legend needs the same answer, and two parsers that had to agree on the
    /// same five emoji is the bug this file already paid for once elsewhere.
    ///
    /// **Keyed by the first scalar, not by the `Character`.** `◀️` is `◀` plus
    /// U+FE0F and Swift reads the pair as *one* grapheme, so a table written
    /// with the bare triangle matches nothing and every chord came out as a
    /// mouse with a stray blue arrow beside it.
    private static func parse(_ chord: String) -> (pressed: Glyphs.Buttons, repeats: Int, movement: String) {
        let byEmoji: [Unicode.Scalar: Glyphs.Buttons] = [
            "◀": .left, "▶": .right, "🛞": .wheel, "🔼": .forward, "🔽": .back,
        ]
        var pressed: Glyphs.Buttons = []
        var seen = 0
        var rest = ""
        for ch in chord {
            if let first = ch.unicodeScalars.first, let button = byEmoji[first] {
                if pressed.contains(button) { seen += 1 } else { pressed.insert(button) }
            } else {
                rest.append(ch)
            }
        }
        let movement = rest.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "+"))
            .trimmingCharacters(in: .whitespaces)
        return (pressed, seen, movement)
    }

    /// **The one place the panel asks which vocabulary is live.** Victor's ask
    /// of 2026-09-22 — *"ajustat după alegerea actuală de gestures"* — is this
    /// pair of accessors and nothing else: everything below reads the active
    /// chord, so the panel describes the mouse in his hand rather than both
    /// mice he could have configured.
    private static func chord(of g: Gesture) -> String { logiGesturesOn ? g.logi : g.wheel }
    private static func glyph(of g: Gesture) -> String { logiGesturesOn ? g.logiGlyph : g.wheelGlyph }
    /// What to call it in a heading.
    private static var vocabulary: String { logiGesturesOn ? "Logi" : "Wheel" }

    // MARK: - The gestures

    /// **The chord read back into a picture.** The menu writes a gesture as an
    /// emoji for the button and a text arrow for the movement — `🔼 →` — and this
    /// turns the first half into the drawing and leaves the second half as it is.
    /// A chord whose buttons it does not recognise (`⌘⇧P`) keeps its whole string
    /// and gets no drawing, which is the honest rendering of a gesture the mouse
    /// has no part in.
    private static func drawn(_ chord: String) -> NSView {
        let (pressed, seen, movement) = parse(chord)
        guard !pressed.isEmpty else {
            return label(chord, size: 11, weight: .medium, colour: .secondaryLabelColor)
        }
        var views: [NSView] = [viewFor(pressed, height: 30)]
        // `🛞🛞` is one picture and a count, not two mice.
        if seen > 0 { views.append(label("×\(seen + 1)", size: 11, colour: .secondaryLabelColor)) }
        if !movement.isEmpty { views.append(label(movement, size: 13, weight: .semibold)) }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        return row
    }

    /// **Every cell of the gesture table is a fixed width**, and that is the
    /// difference between a table and five rows that happen to be near each
    /// other. The chord cell's *content* varies enormously — a bare `⌘⇧P`, a
    /// mouse seen from above at 15pt wide, the flank at 74 — so a stack that
    /// sized itself to its content put the `în meniu` glyph in a different
    /// place on every row, which is exactly the column the caption tells the
    /// reader to look down. Rendering the panel is what showed it.
    private static func cell(_ view: NSView, width: CGFloat) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width),
            box.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor),
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            view.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor),
        ])
        return box
    }

    /// The column widths, in one place because the header row and the body
    /// rows both have to agree with them or the table is not one.
    private static let colWhat: CGFloat = 196
    private static let colChord: CGFloat = 148
    private static let colGlyph: CGFloat = 62
    /// What the widest thing on the panel comes to, so the prose wraps to the
    /// table rather than to whatever the window has been dragged out to.
    private static let tableWidth: CGFloat = colWhat + colChord + colGlyph + 2 * 12
    /// The legend's text column: the panel's width less the drawing beside it.
    private static let legendTextWidth: CGFloat = tableWidth - 62 * MouseView.aspect - 14

    private static func gestureTable() -> [NSView] {
        guard !gestures.isEmpty else { return [] }

        // **Only the vocabulary that is live.** It printed both, side by side,
        // with the inactive pair faded — which put four columns on the panel to
        // describe a mouse that has one set of gestures at a time. Victor's
        // *"ajustat după alegerea actuală de gestures"* settles it: the panel
        // is a legend for the mouse in his hand, and the set he is not using is
        // one menu row away.
        var rows: [NSView] = [
            heading("What each gesture does — \(vocabulary)"),
            label("""
                  The “in menu” column is the glyph the menu draws at the right \
                  of that row, in the same column as “>”.
                  """, size: 11, colour: .secondaryLabelColor, width: tableWidth, wraps: true),
            headerRow(),
        ]
        for g in gestures {
            let cells: [NSView] = [
                label(g.label, size: 12, width: colWhat, wraps: true),
                cell(drawn(chord(of: g)), width: colChord),
                cell(label(glyph(of: g), size: 13), width: colGlyph),
            ]
            let row = NSStackView(views: cells)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            row.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 3, right: 0)
            rows.append(row)
        }
        return rows
    }

    private static func headerRow() -> NSView {
        let cells = [
            label("", size: 11, width: colWhat),
            label("gesture", size: 11, weight: .semibold, colour: .tertiaryLabelColor, width: colChord),
            label("in menu", size: 11, weight: .semibold, colour: .tertiaryLabelColor, width: colGlyph),
        ]
        let row = NSStackView(views: cells)
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    // MARK: - Small type helpers

    private static func label(_ text: String, size: CGFloat,
                              weight: NSFont.Weight = .regular,
                              colour: NSColor = .labelColor,
                              width: CGFloat? = nil,
                              wraps: Bool = false) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = colour
        f.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        f.maximumNumberOfLines = wraps ? 0 : 1
        f.translatesAutoresizingMaskIntoConstraints = false
        if let width {
            f.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return f
    }

    private static func heading(_ text: String) -> NSView {
        let f = label(text, size: 15, weight: .semibold)
        let box = NSStackView(views: [f])
        box.orientation = .vertical
        box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        return box
    }

    /// The repository, as a link that opens in the browser — the one thing on
    /// this panel that still belongs there, and the whole point of the row that
    /// opens it.
    private static func link(_ url: String) -> NSView {
        let f = NSTextField(labelWithAttributedString: NSAttributedString(
            string: url,
            attributes: [.link: URL(string: url) as Any,
                         .font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.linkColor,
                         .underlineStyle: NSUnderlineStyle.single.rawValue]))
        f.allowsEditingTextAttributes = true
        f.isSelectable = true
        return f
    }

    // MARK: - The whole panel, top to bottom

    private static func content() -> [NSView] {
        var views: [NSView] = [
            label("🎙️ Victor's Walkie Talkie", size: 20, weight: .bold),
            label("built \(buildStamp)", size: 11, colour: .tertiaryLabelColor),
            label("""
                  A menu bar relay: dictate with the mouse, and the words land \
                  in the Claude Code session it is bound to.
                  """, size: 12, colour: .secondaryLabelColor, width: tableWidth, wraps: true),
            heading("Your mouse, button by button — \(vocabulary)"),
        ]

        views += buttons.map(buttonRow)

        views += gestureTable()
        views.append(heading("Source"))
        views.append(link(repository))
        return views
    }
}
