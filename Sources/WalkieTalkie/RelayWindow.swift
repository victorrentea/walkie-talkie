import AppKit

/// The floating, translucent, always-on-top overlay.
///
/// It is a **dictation helper only** — there is no text entry and no selection
/// shortcut. Everything it reports happens by itself: Wispr starts listening,
/// the selection and the screen are captured, the transcript is relayed.
///
/// Interaction is therefore minimal:
///   drag           move it
///   single click   pause / resume forwarding
///   hover          reveal the ✕ (ends the session) and go opaque
///
/// Because it never takes keyboard focus, `canBecomeKey` stays false: the overlay
/// must never steal the caret from whatever Victor is actually working in.
final class RelayWindow: NSObject, NSWindowDelegate {

    private let panel: RelayPanel
    private let root: RelayView
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton = CloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private let cancelButton = PillButton(frame: NSRect(x: 0, y: 0, width: 116, height: 28))
    /// **The countdown moved onto Send.** The clock was on Cancel, which made the
    /// one destructive control the only one worth looking at and left "it is
    /// going out in 3s" to be inferred from "you can still stop it for 3s". Send
    /// says the same seconds as an offer — and it is a button, so the wait can be
    /// skipped whenever he already knows the text is right.
    private let sendButton = PillButton(frame: NSRect(x: 0, y: 0, width: 128, height: 28))
    /// The engine row: a slowly pulsing 🔴 and the name of whatever is listening.
    ///
    /// **Which ear is open is a fact about the dictation, not about the app**, and
    /// since the relay grew a microphone of its own it is a fact with two possible
    /// answers — Wispr Flow, or the local model. The pulse says *recording* and
    /// the name says *into what*; before this they were one glyph saying only the
    /// first half, at a time when there was nothing else it could have meant.
    private let engineRow = NSView()
    private let recordDot = NSTextField(labelWithString: "🔴")
    private let engineInfo = NSTextField(labelWithString: "")
    /// The recording row: how many shots this dictation is carrying, and how to
    /// add another.
    private let recordRow = NSView()
    private let shotGlyph = NSTextField(labelWithString: "📸")
    private let recordInfo = NSTextField(labelWithString: "")
    /// Elements ⌘-picked in Chrome and still waiting for the sentence they belong
    /// to — how many, and what the newest one was.
    ///
    /// A glyph and a label in a row, exactly like the recording row above it. Not
    /// for the animation (nothing pulses here) but for the geometry: a glyph
    /// measures narrower in the monospaced font than it draws, so inline it stole
    /// a character's worth of width and AppKit truncated it away. Giving the glyph
    /// its own box also lines this row's text up with the recording row's, which
    /// is what makes the two read as one column.
    ///
    /// The glyph is **Chrome's own icon**: the gesture exists in Chrome and
    /// nowhere else, so the browser it works in is the one thing the row can say
    /// without words. The 🎯 it replaced said "aim at something", which is what
    /// the words beside it already say.
    private let pickRow = NSView()
    private let pickGlyph = NSImageView()
    private let pickInfo = NSTextField(labelWithString: "")

    /// The title, in a row of its own so a glyph can sit beside it.
    ///
    /// It was a bare label until the relay learned to point at a terminal. The
    /// mark for that is a **drawn** map pin (`Glyphs.mapPin`) rather than 📍,
    /// which is `ROUND PUSHPIN` and draws as a pin stuck in at an angle — and a
    /// drawn mark cannot go inline, because `attributedStringValue` on these
    /// labels renders the image and turns every other glyph transparent. So the
    /// title joins the pattern the ⌘-pick row already uses: a glyph in its own
    /// box, a label beside it, the two lining up into a column.
    private let titleRow = NSView()
    private let titleGlyph = NSImageView()

    /// The bound terminal's working directory, on a row of its own.
    ///
    /// It used to ride on the title after a `·`, which put two different kinds of
    /// answer on one line — *what the agent is doing* and *where it is doing it* —
    /// and made the chip as wide as the two of them together, beside the cursor,
    /// over Victor's work. Split, each row is short and the eye picks the one it
    /// came for.

    var onTogglePause: (() -> Void)?
    var onEndSession: (() -> Void)?
    /// How a displayed prompt ended: `true` — release it to the agent (the hold
    /// ran out, or he clicked the overlay away), `false` — he pressed Cancel and
    /// it must never be written. Fires exactly once per prompt.
    var onPromptResolved: ((Bool) -> Void)?

    private(set) var selection: String?

    /// How many highlights the dictation is carrying, frozen one included. Zero
    /// when there is no selection row at all.
    private var selectionCount = 0
    private var paused = false
    /// True while the local Whisper model is loading — see `titleText`.
    private var engineLoading = false
    private var listening = false
    /// The relay's own microphone is the one that is open, not Wispr's.
    private var localListening = false
    private var hovering = false

    private var followTimer: Timer?
    private var labelTimer: Timer?
    /// Shots this dictation is carrying — the automatic context capture included,
    /// since from where Victor sits it is simply the first picture taken.
    private var shotCount = 0
    /// Elements ⌘-picked in Chrome, waiting on a sentence.
    private var pickCount = 0
    private var pickNewest: String?
    /// The prompt about to be relayed to the agent, shown whole while it is held
    /// back — the seconds during which Cancel can still stop it.
    private var sentPrompt: String?
    private var promptTimer: Timer?
    /// When the held prompt is due to be released. Drives the Cancel countdown,
    /// so the button says how long Victor still has rather than making him guess.
    private var promptDeadline: Date?
    private var countdownTimer: Timer?
    /// Transient status occupying the subtitle row; nil = no flash in progress.
    private var flashMessage: String?
    /// The terminal dictations are being typed into — `folder@branch` of the
    /// bound session, or nil while the relay is only writing the outbox.
    private var boundLabel: String?
    /// The bound terminal's working directory, `petclinic@main` — **the one thing
    /// the chip says** once it is bound. nil for targets with no tty to read one
    /// from, where the app's own name takes the line rather than inventing a
    /// folder.
    private var boundFolder: String?
    /// The destination app's own icon — Terminal's, Visual Code's, IntelliJ's —
    /// drawn where the pin used to be.
    ///
    /// It replaces the pin because the pin only ever said *bound*, which the
    /// presence of a folder name already says. Which of the three apps is
    /// receiving the words is the fact that actually differs between bindings,
    /// and an icon is the one way to carry it in a chip this narrow: it costs the
    /// space the pin was already taking and is read without being read.
    private var boundIcon: NSImage?
    /// Re-read the bound terminal's title; the branch timer's other half.
    var onRefreshBound: (() -> Void)?
    private weak var homeScreen: NSScreen?

    // MARK: Geometry
    private let pad: CGFloat = 12
    private let rowGap: CGFloat = 6
    private let margin: CGFloat = 24
    /// Space kept clear on the title row for the hover-revealed ✕.
    private let closeReserve: CGFloat = 26
    /// Between Send and Cancel.
    private let buttonGap: CGFloat = 8

    /// **One face for the whole overlay, and one scale.**
    ///
    /// The title used to be the system face and everything under it monospaced,
    /// which made the chip read as two things stacked rather than one card: the
    /// folder in one typeface, the row saying what is listening in another,
    /// three pixels apart. The monospaced face is the one that has to stay — the
    /// ⌘-pick row carries `div.card > span.price`, which a proportional face
    /// turns into prose — so it is the one everything else joined.
    ///
    /// Sizes are the old ones ×1.3, asked for after a session across the room
    /// from the screen: 13 → 17, 12 → 16, 11 → 14. Every box the text sits in is
    /// scaled with it (`recordRowHeight`, `titleRowHeight`, the glyph sizes), or
    /// the letters grow into a row that clips them.
    private let titleFont = NSFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
    private let promptFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private let hintFont = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)

    private func measure(_ s: String, font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// Height of `s` wrapped into `width`.
    private func measureWrapped(_ s: String, font: NSFont, width: CGFloat) -> CGFloat {
        let rect = (s as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height) + 2
    }

    /// The two ways to take one more shot. They appear in the recording row
    /// rather than in a legend of its own: while dictating they are the only
    /// inputs that do anything, and they belong next to the count they increment.
    ///
    /// **The mouse comes first because it is the one that needs saying.** F3 has
    /// been there all along; the back button being borrowed mid-dictation is new,
    /// it lasts only as long as the recording row is up, and unadvertised it
    /// would read as the Return key having broken. Naming it here means the row
    /// and the behaviour appear and disappear together.
    ///
    /// Written as tight as it goes — `🖱️/F3`. The word "back" went too: the mouse
    /// glyph is the mouse, and which of its buttons is the one the hand already
    /// knows by the second dictation. The row rides under the cursor over his
    /// actual work, so every character it does not need is width taken from the
    /// thing he is looking at underneath.
    private static let shotHint = "— mouse/F3 for more shots"

    /// The subtitle row is now flashes only. The shortcut legend used to live here
    /// and has moved into the recording row, where it sits beside the number it
    /// changes instead of being a separate line of instructions.
    ///
    /// Flashes must survive the idle case: the Accessibility warning fires at
    /// launch, long before any dictation, and would be invisible if this row only
    /// ever appeared while listening.
    private var hintText: String? { flashMessage }

    /// The recording row shows **only while dictating and not paused** — the one
    /// window in which there is a recording to report and in which F3 and the
    /// back button do anything. Wispr keeps reporting that it is listening while
    /// forwarding is off, so advertising them in that state would be a lie — and
    /// for the mouse it would be worse than a lie: paused is exactly when the
    /// button is handed back to LinearMouse and types Return again.
    private var recordText: String? {
        guard listening, !paused else { return nil }
        return "\(shotCount) \(Self.shotHint)"
    }

    /// What is happening, and what is doing it — beside the pulse that says it is
    /// happening *now*.
    ///
    /// **The verb is said, not left to the dot.** The row used to be the engine's
    /// name alone (`Wispr Flow`), on the reading that a pulsing red dot already
    /// means recording. It does to whoever built it; to a room seeing the overlay
    /// for the first time — and to Victor at a glance, mid-sentence — a bare
    /// product name beside a light is a status *badge*, not an event. `Listening
    /// with Wispr Flow` is the same two facts in the order they are asked in: is
    /// it listening, and who is listening.
    ///
    /// **`Listening`, not `Recording`.** Recording is what a device does to a
    /// file; listening is what the other end of a conversation does, and this
    /// row is on screen precisely while Victor is talking *to* something.
    ///
    /// The engine is still spelled out rather than abbreviated: it answers the
    /// question the whole engine switch exists for — which of the two recognisers
    /// is about to be believed. The local one is on trial, and it is the one whose
    /// transcript nothing else can double-check.
    private var engineText: String? {
        guard listening, !paused else { return nil }
        return "Listening with " + (localListening ? "Local Whisper" : "Wispr Flow")
    }

    /// The gesture that picks an element out of the page — shown **only while
    /// dictating**, exactly like `shotHint`, because that is the only window in
    /// which ⌘⇧ in Chrome belongs to the relay at all.
    ///
    /// It has to be advertised for the same reason the borrowed mouse button does:
    /// ⌘⇧-click opens a link in a new tab and jumps to it, and a browser that
    /// silently stopped doing that would read as broken. The hint and the
    /// behaviour appear and disappear together, and the row rides beside the
    /// cursor — which is where his eyes already are while he points at things.
    ///
    /// It names **what the gesture does**, not how the keys are held. `hold` was
    /// there to explain the 400ms arming delay, but a hint whose first word is a
    /// mechanic describes the input and leaves the outcome unsaid — and the
    /// outcome is the only half worth a row beside the cursor. The chord and the
    /// mouse still follow it, so the delay is still discoverable by trying it.
    private static let pickHint = "— ⌘⇧+click to select element"

    /// The picked-elements row: the gesture until he has used it, the newest thing
    /// he picked once he has.
    ///
    /// The hint gives way to the name because after the first pick the question
    /// changes. Before it, the only thing worth saying is *that you can do this*;
    /// after it, he knows the gesture and what he cannot check without a name is
    /// whether the click caught the button or the div wrapped around it. A count
    /// alone (`×3`) only tells him something he already believes.
    ///
    /// Gated on `listening` like the recording row above it, and hidden while
    /// paused for the same reason: with ⌘⇧ handed back to Chrome, a row saying
    /// otherwise is a lie about which gestures are live.
    private var pickText: String? {
        guard listening, !paused else { return nil }
        guard pickCount > 0 else { return Self.pickHint }
        guard let newest = pickNewest, !newest.isEmpty else { return "×\(pickCount)" }
        return "×\(pickCount) \(Self.fit(newest, 34))"
    }

    /// Keep the tail, drop the head. A selector's last steps are the element; its
    /// first steps are the page, which he is looking at.
    private static func fit(_ s: String, _ limit: Int) -> String {
        s.count <= limit ? s : "…" + String(s.suffix(limit - 1))
    }

    private var screenWidth: CGFloat {
        (panel.screen ?? NSScreen.main)?.frame.width.rounded() ?? 1440
    }

    override init() {
        panel = RelayPanel(
            // Placeholder — `layoutContent()` sizes the panel to its content
            // before it is ever shown.
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        root = RelayView(frame: panel.contentLayoutRect)
        super.init()

        configurePanel()
        configureViews()
        layoutContent()
        positionInitially()
        startFollowingMouse()
        startWatchingTyping()
        startWatchingBranch()
        panel.orderFrontRegardless()
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false      // we drag manually
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Keeps the overlay out of every screenshot — verified: a capture taken by
        // a separate process, with no hiding at all, does not contain it.
        // …which also makes the overlay impossible to *look at* while working on
        // it: no screenshot can contain it, so nobody debugging its appearance
        // can see what Victor sees. RELAY_CAPTURABLE=1 asks for it back, and is
        // off in every normal run.
        //
        // Measured 2026-07-31 on macOS 15: it no longer works. `.readOnly` gets a
        // fully transparent image out of `screencapture`, whole-display or
        // `-l <windowid>`. Until someone finds the new lever, the way to check a
        // layout change is `CGWindowListCopyWindowInfo` — the window's bounds tell
        // you which rows are up (16 title / 17 recording / 15 selection, 6 apart,
        // 12 padding all round) and whether it is riding the cursor.
        panel.sharingType = ProcessInfo.processInfo.environment["RELAY_CAPTURABLE"] == "1"
            ? .readOnly : .none
        panel.delegate = self
        panel.contentView = root
        root.owner = self
    }

    private func configureViews() {
        // The shine sweeps as a sublayer of the root layer, so the root needs to
        // be layer-backed and clip to the same rounded rect as the blur.
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        root.addSubview(blur)
        root.blur = blur

        titleLabel.font = titleFont
        titleLabel.textColor = .labelColor
        titleGlyph.image = Self.pinGlyph
        titleGlyph.imageScaling = .scaleProportionallyUpOrDown
        // The box is as wide as the widest icon on the card, so without this the
        // image would sit centred in it — half a column right of the emoji above
        // and below, which is the misalignment the shared column was meant to fix.
        titleGlyph.imageAlignment = .alignLeft
        titleGlyph.isHidden = true          // only a bound relay shows a destination
        titleRow.addSubview(titleGlyph)
        titleRow.addSubview(titleLabel)
        root.addSubview(titleRow)

        hintLabel.font = hintFont
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.isHidden = true            // summoned by layoutContent when there is something to say
        root.addSubview(hintLabel)

        // Two labels rather than one string, because only the dot pulses: an
        // animation on the whole row would blink the engine's name too, and a
        // word that fades in and out is a word he has to wait to read.
        recordDot.font = .systemFont(ofSize: 14)
        recordDot.alignment = .left
        recordDot.wantsLayer = true
        engineInfo.font = hintFont
        engineInfo.textColor = .secondaryLabelColor
        engineRow.addSubview(recordDot)
        engineRow.addSubview(engineInfo)
        engineRow.isHidden = true
        root.addSubview(engineRow)

        shotGlyph.font = .systemFont(ofSize: 14)
        shotGlyph.alignment = .left
        recordInfo.font = hintFont
        recordInfo.textColor = .secondaryLabelColor
        recordRow.addSubview(shotGlyph)
        recordRow.addSubview(recordInfo)
        recordRow.isHidden = true
        root.addSubview(recordRow)

        // Monospaced, like the recording row: what it carries is a CSS selector,
        // and a proportional font makes `div.card > span.price` read as prose.
        pickGlyph.image = Self.browserIcon
        pickGlyph.imageScaling = .scaleProportionallyUpOrDown
        pickGlyph.imageAlignment = .alignLeft
        pickInfo.font = hintFont
        pickInfo.textColor = .secondaryLabelColor
        pickInfo.lineBreakMode = .byTruncatingHead   // the tail is the element
        pickInfo.maximumNumberOfLines = 1
        pickRow.addSubview(pickGlyph)
        pickRow.addSubview(pickInfo)
        pickRow.isHidden = true
        root.addSubview(pickRow)

        selectionLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        selectionLabel.textColor = .secondaryLabelColor
        selectionLabel.lineBreakMode = .byTruncatingTail
        selectionLabel.maximumNumberOfLines = 1
        selectionLabel.cell?.truncatesLastVisibleLine = true
        selectionLabel.isHidden = true
        root.addSubview(selectionLabel)

        promptLabel.font = promptFont
        promptLabel.textColor = .labelColor
        promptLabel.isHidden = true
        promptLabel.maximumNumberOfLines = 0        // wrap freely; the height follows
        root.addSubview(promptLabel)

        closeButton.isHidden = true          // revealed on hover, like a notification
        closeButton.onClick = { [weak self] in self?.onEndSession?() }
        root.addSubview(closeButton)

        // Not hover-revealed like the ✕: this one is on a clock, so it has to be
        // visible and clickable the instant the prompt appears.
        cancelButton.isHidden = true
        cancelButton.onClick = { [weak self] in self?.resolvePrompt(send: false) }
        root.addSubview(cancelButton)

        // Left of Cancel, and not red: it is the button that does what he already
        // meant to do. Red is kept for the one that throws the dictation away.
        sendButton.isHidden = true
        sendButton.accent = .controlAccentColor
        sendButton.onClick = { [weak self] in self?.resolvePrompt(send: true) }
        root.addSubview(sendButton)

        refreshTitle()
    }

    // MARK: - Placement

    private func moveToTopLeft(of screen: NSScreen) {
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.minX + margin,
            y: area.maxY - panel.frame.height - margin
        ))
        homeScreen = screen
    }

    private func positionInitially() { reposition() }

    /// At rest the overlay is an **anchor**, not a panel: nothing is happening, so
    /// the only thing worth saying is *which agent this is* — 🤖 folder@branch —
    /// and the only place worth saying it is wherever Victor is already looking,
    /// which is wherever his cursor is. Parked in a corner it was either unseen
    /// or pointless; here it is a label on the work in front of him.
    ///
    /// A prompt or a warning still turns it into the panel, in its corner. **A
    /// dictation no longer does.** That threw the panel across his work for the
    /// whole time he talked — the longest stretch the big overlay was ever on
    /// screen, and the one where it had the least to say. The recording row (🔴,
    /// the shot count, F3) is small enough to ride along under the chip, right
    /// where he is already looking. The panel is now kept for the one thing he
    /// must actually read: the prompt about to be sent.
    ///
    /// **Paused is anchored too.** It used to become a panel in the corner, on the
    /// argument that pausing was the only route to a ✕ at rest. The menu bar item
    /// now carries both Pause/Resume and Quit, so that argument is gone — and what
    /// is left is the fact that pause is a state he stays in for minutes at a time
    /// while dictating into other apps. A half-screen panel parked over his work
    /// for all of it says nothing he doesn't already know. The chip says it where
    /// he is looking: ⏸️ in front of the robot, at 0.30.
    /// **A flash is anchored too, since 2026-08-26.** It used to throw the panel
    /// into the top-left corner — `⏳ loading the local model`, `🎙️ ready`, every
    /// warning — which put the overlay's words in two different places depending
    /// on which kind of word it was. Victor read the corner as a *second*,
    /// unrelated thing on screen ("e confuzant"), and he is right: the eye that
    /// has learned to find this app beside the pointer has no reason to go
    /// looking in a corner for the rest of it. The prompt is the one thing left
    /// that earns the panel, because it is the one thing he has to read whole
    /// before a clock runs out.
    private var anchored: Bool { sentPrompt == nil }

    /// Where the chip rides relative to the pointer: below and to the right, out
    /// of the way of the thing being pointed at.
    private let anchorGap = NSSize(width: 10, height: 22)

    /// The middle of the chip in screen coordinates — what the bind rectangle
    /// flies into. Asked for live, since the chip is following the pointer while
    /// the rectangle is in the air.
    var chipCentre: CGPoint {
        CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    }

    /// Tracking has two states, and the second one is what keeps the ✕ reachable.
    ///
    /// **Engaged** — the cursor is moving, so the chip is pinned to it every
    /// frame. Anything less (a leash, a "catch up when far enough" rule) reads as
    /// lag, because it *is* lag: the chip visibly trails behind the pointer.
    ///
    /// **Settled** — the cursor has stopped, so the chip stops with it and stays
    /// put until he goes somewhere (`wakeDistance`). That is the window in which
    /// he can walk the pointer over to it and click: a chip that re-engages on
    /// the first pixel of movement can never be caught, and with the ✕ living on
    /// it that would mean no way to end a session at rest.
    private var engaged = false
    /// He has the mouse down *on the overlay* — the only gesture that may move it
    /// by hand, and the only one tracking must yield to.
    private var draggingSelf = false
    /// He is typing, so macOS has hidden the pointer and the chip has nothing
    /// left to be anchored to.
    private var typing = false
    private var typingMonitor: Any?
    private var settlePoint = NSPoint.zero
    private var lastMouse = NSPoint.zero
    private var stillTicks = 0
    /// ~0.25s of stillness at 60 Hz.
    private let settleTicks = 15
    private let wakeDistance: CGFloat = 70

    /// macOS hides the pointer the moment he starts typing — in a terminal, in an
    /// editor — and a chip anchored to an invisible pointer is a label sitting in
    /// the middle of his text with nothing to explain it. There is no supported
    /// API left to ask whether the pointer is drawn (`CGCursorIsDrawnInFramebuffer`
    /// is gone), so the chip watches the cause instead of the effect: a keystroke
    /// sends it away, the next mouse movement brings it back.
    ///
    /// A passive global monitor — it observes, never intercepts, and needs the
    /// Accessibility grant the overlay already has for its own shortcut.
    private func startWatchingTyping() {
        typingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            guard let self = self, !self.typing else { return }
            self.typing = true
            self.refreshOpacity()
        }
    }

    private func startFollowingMouse() {
        // 60 Hz: while engaged this is a window move per frame, which is what
        // "follows the mouse" costs. Settled, it is two point comparisons.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.followCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func followCursor() {
        // The first real movement of the pointer brings the chip back after
        // typing sent it away.
        if typing, hypot(NSEvent.mouseLocation.x - lastMouse.x,
                         NSEvent.mouseLocation.y - lastMouse.y) > 1 {
            typing = false
            refreshOpacity()
        }

        // Only a drag *of the overlay* suspends tracking. Testing
        // `pressedMouseButtons` instead meant any drag anywhere froze the chip —
        // he'd select a paragraph or drag a file and the label would sit where
        // the gesture started, which is the one moment it looks broken.
        guard !draggingSelf else { return }
        guard let screen = Self.screenUnderMouse() else { return }

        // In the panel states only the *screen* follows: Victor works on whichever
        // screen he points at, and a panel stranded on the other monitor is a
        // panel he cannot see. Where it sits on that screen is left alone, so a
        // overlay he dragged out of the way stays out of the way.
        guard anchored else {
            if screen !== homeScreen { moveToTopLeft(of: screen) }
            return
        }

        let mouse = NSEvent.mouseLocation
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        lastMouse = mouse

        if engaged {
            stillTicks = moved < 1 ? stillTicks + 1 : 0
            if stillTicks >= settleTicks {
                engaged = false
                settlePoint = mouse
                return
            }
            moveNextTo(mouse, on: screen)
            return
        }

        // Settled: wake on a real journey, not on the nudge that is him reaching
        // for the chip itself.
        if hypot(mouse.x - settlePoint.x, mouse.y - settlePoint.y) > wakeDistance || screen !== homeScreen {
            engaged = true
            stillTicks = 0
            moveNextTo(mouse, on: screen)
        }
    }

    /// Below-right of the cursor. **Always** below-right: it used to flip and
    /// clamp near the screen edges to stay fully visible, which meant the chip
    /// jumped to the other side of the pointer exactly when he ran the cursor
    /// into the right-hand edge. A label that moves relative to what it labels is
    /// worse than a label half off-screen, so it keeps its offset and lets the
    /// edge cut it.
    private func moveNextTo(_ mouse: NSPoint, on screen: NSScreen) {
        panel.setFrameOrigin(NSPoint(x: mouse.x + anchorGap.width,
                                     y: mouse.y - anchorGap.height - panel.frame.height))
        homeScreen = screen
    }

    /// Called on every entry to and exit from a panel state, so the move happens
    /// with the state change rather than whenever the leash next gives.
    private func reposition() {
        guard let screen = Self.screenUnderMouse() ?? NSScreen.main else { return }
        if anchored {
            engaged = true
            stillTicks = 0
            moveNextTo(NSEvent.mouseLocation, on: screen)
        } else {
            moveToTopLeft(of: screen)
        }
    }

    /// The title is `folder@branch`, and he switches branches mid-session — a
    /// overlay still claiming `@master` would be quietly wrong about which branch
    /// is receiving his dictation. Ten seconds is slow enough to be free (one
    /// `git rev-parse`) and fast enough that he never reads a stale name.
    private func startWatchingBranch() {
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // The bound terminal's title rides this tick rather than one of its
            // own: both are the same question — "is the name on the chip still
            // true?" — asked of two different sources, and an agent renaming its
            // window is exactly as slow-moving as Victor switching branches.
            // It is asked unconditionally, ahead of the early return: a title
            // that changed while the branch did not is the common case.
            self.onRefreshBound?()
            guard SessionLabel.refresh() else { return }
            self.applyTitleText()
            self.layoutContent()          // the title drives the overlay's width
        }
        RunLoop.main.add(timer, forMode: .common)
        labelTimer = timer
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Layout

    /// Manual layout in one pass: build the visible rows top-down with their
    /// heights, size the window to their total, then place them.
    private func layoutContent(animated: Bool = false) {
        // Hug the content of the *current* state, not the widest state there is:
        // standing by is what the overlay does for hours, and it should take no
        // more room than "🤖 ai@master" needs. Changing state resizes it, which is
        // fine.
        // Asked of the label, not of the font — the 🤖 draws wider than the
        // semibold metrics say, so `measure` clipped the last character of the
        // session name whenever the title was the widest row. It only became
        // visible once a state existed where it *was* the widest: before the
        // ⌘-pick row, something longer was always beside it.
        titleLabel.stringValue = titleText
        titleLabel.sizeToFit()
        // The pin sits in its own box ahead of the text, so it counts too.
        let titleWidth = ceil(titleLabel.frame.width) + (boundLabel != nil ? glyphColumn + recordDotGap : 0)
        // A row's width only counts while that row is actually there. It used to
        // be reserved permanently to keep the overlay from jumping sideways when
        // dictation starts, but that reservation is exactly the empty space that
        // has no business being there the rest of the time.
        let hintWidth = hintText.map { measure($0, font: hintFont) } ?? 0
        let engineWidth = engineText.map { rowWidth($0) } ?? 0
        let recordWidth = recordText.map { rowWidth($0) } ?? 0
        let pickWidth = pickText.map { glyphRowWidth($0) } ?? 0
        // No ✕ at rest means no room kept for one: the chip is exactly its text.
        let reserve = anchored ? 0 : closeReserve
        // The two buttons are a row like any other and have to be measured like
        // one. With only Cancel on it that was survivable; Send beside it is
        // 252pt of control, which a short dictation's panel is narrower than —
        // and a button laid out past the left edge is a button he cannot press.
        let buttonsWidth = sentPrompt == nil ? 0
            : sendButton.frame.width + buttonGap + cancelButton.frame.width
        let natural = ceil(max(titleWidth + reserve,
                               max(buttonsWidth,
                                   max(hintWidth, max(engineWidth, max(recordWidth, pickWidth)))))) + pad * 2

        // Only a prompt earns the full half-screen. It has to be read whole, and
        // read *fast*, because the Cancel clock is running.
        //
        // A selection does not. Widening the moment dictation starts throws a
        // half-screen panel across whatever Victor is looking at for the entire
        // time he talks — to show him text he highlighted himself a second ago.
        // It rides along truncated in the narrow overlay instead, which is all the
        // receipt it needs, and the overlay grows only at the end, when there is
        // finally something he has *not* seen: what Wispr actually heard.
        // …and even then it takes only what the text needs. Half the screen is the
        // ceiling, not the size: a four-word dictation in a half-screen panel is
        // mostly empty space parked over his work.
        let promptWidth = sentPrompt.map { prompt in
            // +8 of slack: measuring a line and laying it out disagree by a hair,
            // and a hair is enough to wrap the last two words onto a line the
            // height was not measured for — a receipt that cuts its own last words.
            (prompt.split(whereSeparator: { $0.isNewline })
                   .map { measure(String($0), font: promptFont) }.max() ?? 0) + pad * 2 + 8
        } ?? 0
        let width = sentPrompt != nil
            ? min(max(natural, promptWidth), screenWidth / 2)
            : min(natural, screenWidth / 2)
        let innerWidth = width - pad * 2

        var rows: [(view: NSView, height: CGFloat)] = []

        layoutTitleRow(width: innerWidth)
        rows.append((titleRow, titleRowHeight))

        // First of the three, because it is the one that is *about* the dictation
        // rather than about what is riding along with it: something is listening,
        // and this is what.
        if let engine = engineText {
            engineInfo.stringValue = engine
            layoutGlyphRow(engineRow, glyph: recordDot, label: engineInfo, width: innerWidth)
            engineRow.isHidden = false
            rows.append((engineRow, recordRowHeight))
        } else {
            engineRow.isHidden = true
        }

        // Then what the message is carrying: while he is talking this is the row
        // that changes, and the one he glances down at to check that the shot he
        // just took landed.
        if let record = recordText {
            recordInfo.stringValue = record
            layoutGlyphRow(recordRow, glyph: shotGlyph, label: recordInfo, width: innerWidth)
            recordRow.isHidden = false
            rows.append((recordRow, recordRowHeight))
        } else {
            recordRow.isHidden = true
        }

        // Under the recording row, above the selection: it belongs with the other
        // things this message is carrying, and unlike them it is also there
        // between messages, which is when he needs it most.
        if let pick = pickText {
            pickInfo.stringValue = pick
            layoutPickRow(width: innerWidth)
            pickRow.isHidden = false
            rows.append((pickRow, pickRowHeight))
        } else {
            pickRow.isHidden = true
        }

        if let selection = selection {
            selectionLabel.stringValue = (selectionCount > 1 ? "↪ ×\(selectionCount) " : "↪ ") + singleLine(selection)
            selectionLabel.frame.size = NSSize(width: innerWidth, height: 19)
            selectionLabel.isHidden = false
            rows.append((selectionLabel, 19))
        } else {
            selectionLabel.isHidden = true
        }

        if let prompt = sentPrompt {
            // Vertically: whatever it takes to show the prompt whole, bounded
            // only by the screen so a very long dictation can't grow an overlay
            // taller than the display.
            let maxHeight = ((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - margin * 2 - 80
            promptLabel.stringValue = prompt
            promptLabel.preferredMaxLayoutWidth = innerWidth
            let h = min(measureWrapped(prompt, font: promptFont, width: innerWidth), maxHeight)
            promptLabel.frame.size = NSSize(width: innerWidth, height: h)
            promptLabel.isHidden = false
            rows.append((promptLabel, h))
        } else {
            promptLabel.isHidden = true
        }

        // Its own row rather than an overlay in a corner: the prompt can be many
        // lines long, and a button floating over the last one is a button that
        // sometimes sits on top of a word.
        if sentPrompt != nil {
            cancelButton.isHidden = false
            sendButton.isHidden = false
            rows.append((cancelButton, cancelButton.frame.height))
        } else {
            cancelButton.isHidden = true
            sendButton.isHidden = true
        }

        if let hint = hintText {
            hintLabel.stringValue = hint
            hintLabel.textColor = flashMessage == nil ? .secondaryLabelColor : .labelColor
            hintLabel.frame.size = NSSize(width: innerWidth, height: 22)
            hintLabel.isHidden = false
            rows.append((hintLabel, 22))
        } else {
            hintLabel.isHidden = true
        }

        let contentHeight = rows.reduce(0) { $0 + $1.height }
        let height = contentHeight + rowGap * CGFloat(rows.count - 1) + pad * 2

        // Anchor the TOP edge: the overlay sits in the top-left corner, so it
        // grows downward into empty screen rather than up under the menu bar.
        let oldTop = panel.frame.maxY
        let frame = NSRect(x: panel.frame.minX, y: oldTop - height, width: width, height: height)
        if animated {
            // The jump from a one-line "Listening…" to a half-screen prompt is the
            // biggest thing this window ever does, and done instantly it reads as
            // a new window appearing rather than as this one unfolding.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        root.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        root.blur?.frame = root.bounds

        var y = height - pad
        for row in rows {
            y -= row.height
            row.view.frame.origin = NSPoint(x: pad, y: y)
            y -= rowGap
        }

        // Bottom-right, where Victor asked for it — and where a destructive
        // button belongs, far from the drag area his cursor arrives through.
        if !cancelButton.isHidden {
            cancelButton.frame.origin.x = width - pad - cancelButton.frame.width
            // Send sits on the same line, immediately left of Cancel: the pair
            // reads left-to-right as "send / don't", and the hand that comes for
            // either arrives at the same corner.
            sendButton.frame.origin = NSPoint(
                x: cancelButton.frame.minX - buttonGap - sendButton.frame.width,
                y: cancelButton.frame.origin.y)
        }

        closeButton.frame.origin = NSPoint(x: width - closeButton.frame.width - 6,
                                           y: height - closeButton.frame.height - 6)
        refreshChrome()
        root.needsDisplay = true
    }

    // MARK: The recording row

    private let recordRowHeight: CGFloat = 22
    /// Same as the recording row: the two are the same kind of fact about the
    /// message being assembled, and a row that stood a pixel taller than its
    /// neighbour would read as a different kind of thing.
    private let pickRowHeight: CGFloat = 22
    /// Between the dot and the text. Wide enough that the pulsing dot reads as its
    /// own indicator rather than as punctuation in front of the count.
    private let recordDotGap: CGFloat = 5

    private var recordDotWidth: CGFloat { ceil(measure(recordDot.stringValue, font: recordDot.font!)) }
    private var shotGlyphWidth: CGFloat { ceil(measure(shotGlyph.stringValue, font: shotGlyph.font!)) }

    /// **One column for all three glyphs**, as wide as the widest of them — the
    /// pulse, the camera, Chrome's icon.
    ///
    /// They used to be measured per row, which is fine for one row and wrong for
    /// three: an emoji, a second emoji and a bitmap are three different widths, so
    /// each row's text would start at its own x and the block would read as three
    /// unrelated lines rather than as one thing being assembled. Aligning the
    /// *text* is what makes it a list; aligning the glyphs is what makes it a
    /// column.
    private var glyphColumn: CGFloat {
        max(recordDotWidth, max(shotGlyphWidth, max(pickGlyphWidth, titleGlyphWidth)))
    }

    /// The title row's own height, kept in step with the text in it.
    private let titleRowHeight: CGFloat = 21

    private func rowWidth(_ text: String) -> CGFloat {
        glyphColumn + recordDotGap + ceil(measure(text, font: hintFont))
    }

    /// The emoji sit a pixel high: their ink is smaller than the line box, and
    /// left on the baseline they hang below the text beside them.
    private func layoutGlyphRow(_ row: NSView, glyph: NSView, label: NSView, width: CGFloat) {
        row.frame.size = NSSize(width: width, height: recordRowHeight)
        glyph.frame = NSRect(x: 0, y: 1, width: glyphColumn, height: 15)
        label.frame = NSRect(x: glyphColumn + recordDotGap, y: 0,
                             width: max(0, width - glyphColumn - recordDotGap),
                             height: recordRowHeight)
    }

    /// Chrome's icon as the system has it, looked up by bundle id so it is found
    /// wherever the app was installed and stays right when Google restyles it.
    /// Nothing is shipped alongside the binary, and no version of the logo is
    /// frozen into this repo.
    private static let browserIcon: NSImage = {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            return NSImage(named: NSImage.networkName) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: app.path)
    }()

    /// A square the height of the row's text. Fixed rather than measured: an image
    /// has no font metrics to ask, and the row is laid out around whatever this
    /// says.
    /// Both drawn once and reused: they never change, and re-rasterising a shape
    /// on every relayout would be work done sixty times a second while the chip
    /// follows the cursor.
    private static let pinGlyph = Glyphs.mapPin(height: 18)

    /// The glyph's box on the title row — an app icon when bound to one, the pin
    /// otherwise. Asked of the image that is actually set rather than of the pin,
    /// since the two are not the same width: the pin draws at `0.696 × height`
    /// and an app icon is square, and reserving the wrong one clips the folder
    /// name by exactly the difference.
    private var titleGlyphWidth: CGFloat { ceil((titleGlyph.image ?? Self.pinGlyph).size.width) }

    private static let pickGlyphSize: CGFloat = 17

    private var pickGlyphWidth: CGFloat { Self.pickGlyphSize }

    /// Same shape as `recordRowWidth`, so the ⌘-pick row and the recording row
    /// can never disagree about where their text starts — but it asks the **label**
    /// how wide the text is instead of asking the font.
    ///
    /// `measure` is a font metric, and this row is the one place it is not enough:
    /// `×` is not in the monospaced face, so it falls back to a font those metrics
    /// know nothing about. The result was a couple of
    /// characters of underestimate, which is exactly enough for AppKit to
    /// ellipsize — and since the tail is the part worth keeping, what it ate was
    /// the count at the front. The rows above tolerate the same error only because
    /// they do not truncate at all.
    private func glyphRowWidth(_ text: String) -> CGFloat {
        pickInfo.stringValue = text
        pickInfo.sizeToFit()
        return glyphColumn + recordDotGap + ceil(pickInfo.frame.width)
    }

    /// The pin is vertically centred on the row rather than sat on the baseline:
    /// it is a shape, not a letter, and lining its middle up with the text's is
    /// what stops it reading as having slipped.
    /// **The title's icon sits in the same column as every other icon**, and its
    /// text starts where every other row's text starts.
    ///
    /// It used to be laid out on its own measurements — the app icon is square,
    /// the pin is `0.696 × height`, the emoji below are something else again —
    /// so the folder name began at one x, the engine row at a second and the
    /// ⌘-pick row at a third. Four rows, four left edges, on a card 200px wide.
    /// One column for the icons and one for the text is what makes it a card
    /// rather than four labels that happen to be adjacent.
    private func layoutTitleRow(width: CGFloat) {
        let bound = boundLabel != nil
        titleGlyph.isHidden = !bound
        titleRow.frame.size = NSSize(width: width, height: titleRowHeight)
        let column = bound ? glyphColumn : 0
        let gap = bound ? recordDotGap : 0
        if bound {
            let image = titleGlyph.image ?? Self.pinGlyph
            let h = min(image.size.height, titleRowHeight)
            // Left-aligned in the column, like the others: the box is as wide as
            // the widest icon, and an icon centred in it would sit right of the
            // ones above and below.
            titleGlyph.frame = NSRect(x: 0, y: ((titleRowHeight - h) / 2).rounded(),
                                      width: column, height: ceil(h))
        }
        titleLabel.frame = NSRect(x: column + gap, y: 0,
                                  width: max(0, width - column - gap), height: titleRowHeight)
    }

    private func layoutPickRow(width: CGFloat) {
        let glyphWidth = pickGlyphWidth
        pickRow.frame.size = NSSize(width: width, height: pickRowHeight)
        // Flush left in the shared column, like every other icon on the card.
        pickGlyph.frame = NSRect(x: 0,
                                 y: ((pickRowHeight - glyphWidth) / 2).rounded(),
                                 width: glyphWidth, height: glyphWidth)
        pickInfo.frame = NSRect(x: glyphColumn + recordDotGap, y: 0,
                                width: max(0, width - glyphColumn - recordDotGap),
                                height: pickRowHeight)
    }

    /// At rest there is no window — only the text. A blurred, rounded, shadowed
    /// panel riding along beside the cursor all day is a window following him
    /// around; the same words with nothing behind them are a label on his work.
    /// The panel comes back the moment there is something to *contain*: a
    /// dictation, a prompt, a warning.
    private func refreshChrome() {
        // **Bare is not the same question as anchored any more.** Anchored is
        // *where* the overlay is; bare is whether it draws a window around the
        // words. The chip at rest is bare — a label on his work. A flash is a
        // sentence he has to read once, often over a busy screen, so it keeps
        // the blur and the shadow while riding the pointer like everything else.
        let bare = anchored && flashMessage == nil
        root.blur?.isHidden = bare
        root.layer?.cornerRadius = bare ? 0 : 14
        if panel.hasShadow != !bare {
            panel.hasShadow = !bare
            panel.invalidateShadow()
        }
        // Enforced here and not only on hover: leaving a panel state while the
        // cursor happens to be over the overlay would otherwise strand a ✕ on the
        // chip, since nothing re-enters `setHovering` on the way out.
        closeButton.isHidden = bare || !hovering

        // White glyphs need something to separate them from a white page. A
        // *layer* shadow, since the string-attribute route doesn't render here.
        titleLabel.wantsLayer = true
        recordInfo.wantsLayer = true
        engineInfo.wantsLayer = true
        shotGlyph.wantsLayer = true
        pickInfo.wantsLayer = true
        if bare {
            titleLabel.shadow = Self.halo()
            // Same reasoning as the title, and the recording row now spends its
            // whole life on the chip, over his editor rather than over the blur.
            recordInfo.shadow = Self.halo()
            recordInfo.textColor = .white
            engineInfo.shadow = Self.halo()
            engineInfo.textColor = .white
            // The picked row spends even more of its life on the chip than the
            // recording one: it is up between messages, which is most of the day.
            pickInfo.shadow = Self.halo()
            pickInfo.textColor = .white
        } else {
            titleLabel.shadow = nil
            recordInfo.shadow = nil
            recordInfo.textColor = .secondaryLabelColor
            engineInfo.shadow = nil
            engineInfo.textColor = .secondaryLabelColor
            pickInfo.shadow = nil
            pickInfo.textColor = .secondaryLabelColor
        }
    }

    private static func halo() -> NSShadow {
        let halo = NSShadow()
        halo.shadowColor = NSColor.black.withAlphaComponent(0.9)
        halo.shadowBlurRadius = 3
        halo.shadowOffset = .zero
        return halo
    }

    private func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Title / opacity

    private func refreshTitle() {
        applyTitleText()
        // White on the chip — the one place a hardcoded colour is right. Every
        // other surface in this app sits on the overlay's own blur, which follows
        // the system appearance; the chip sits on his terminal, his editor, a
        // photograph. A dynamic `labelColor` resolves to black in light mode and
        // disappears on a dark terminal, which is exactly what it did.
        titleLabel.textColor = anchored ? .white
                                        : ((paused || !listening) ? .secondaryLabelColor : .labelColor)
        refreshOpacity()
    }

    /// Just the string — kept separate from `refreshTitle` because the dot
    /// animation ticks several times a second and must not restart the opacity
    /// fade on every frame.
    /// Plain `stringValue`, always. **Never `attributedStringValue`**: on these
    /// `NSTextField(labelWithString:)` labels it silently draws nothing but the
    /// emoji — the rest of the glyphs come out fully transparent. That is what
    /// made the chip show a robot head and no session name; measured, not
    /// guessed. Colour and halo go on the label instead (`refreshChrome`).
    private func applyTitleText() {
        titleLabel.stringValue = titleText
    }

    /// The title for the current state.
    ///
    /// Listening has no title of its own any more — no 🎙️, no running dots. The
    /// top line stays 🤖 folder@branch through the whole dictation, because that
    /// is the fact that does not change, and the row below it now carries both the
    /// sign of life (the pulsing 🔴) and everything that does change.
    private var titleText: String {
        // **Loading outranks every other state, including paused**, and it is the
        // only state here that is about the *near future* rather than the present.
        // The model takes ten seconds to come up and a dictation started inside
        // that window is silently handed to the other engine — so the one thing
        // worth saying while it loads is "not yet", and saying it beside the
        // cursor is saying it where he is already looking. It disappears on its
        // own, which is why it can afford to shout over ⏸️ for those seconds.
        if engineLoading { return "⏳ \(identity)" }
        // Paused prefixes the robot rather than replacing it: the chip's job is
        // still to say *which agent this is*, and pause is a modifier on that, not
        // a different thing. Reading ⏸️ ahead of 🤖 is also the same order as the
        // menu bar item, which is the other place the state is shown. No ": Paused"
        // word any more — the glyph plus the fade to 0.30 is the whole message, and
        // the chip rides beside his cursor now, where every character costs room.
        if paused { return "⏸️ \(identity)" }
        // No state word at all. "Stand by" is the one thing he can infer from the
        // fact that nothing is happening; what he cannot infer, and what this chip
        // exists to tell him, is which agent is sitting there waiting.
        return identity
    }

    /// Which agent this is — and, once the relay is bound to a terminal, *where
    /// the words actually go*.
    ///
    /// **Bound replaces the robot rather than decorating it**, because 🤖 has
    /// always meant one specific thing here: this overlay is writing an outbox
    /// that some agent is watching. Bound, that is no longer what happens — the
    /// sentence is typed into a named terminal — and the label changes with it,
    /// from the directory the overlay was *launched* in to the session it is
    /// *pointed* at. Those were always meant to be the same repo and, with two
    /// sessions open in one folder, never reliably were; this is the first time
    /// the chip can say which one by knowing rather than by inheriting.
    ///
    /// **📍 is the one glyph, for every bound target.** It was 🎯 for a target
    /// the relay can interrogate before it types and ⌨️ for one it cannot (VS
    /// Code, IntelliJ), which is a real distinction — it is the difference
    /// between a dictation that gets refused at a shell prompt and one pasted
    /// blind. The pin replaced both because the chip answers *where do my words
    /// go*, and a map pin is the mark for that where two glyphs asking to be
    /// told apart are a legend. The distinction is still shown where it can be
    /// acted on: the flash at bind, `GET /target`, and the refusal itself, which
    /// happens whether or not a glyph advertised that it could.
    ///
    /// **The agent's own title follows the label, after a `·`.** `folder@branch`
    /// says which repo the words are going to, and with two sessions open on the
    /// same branch — which is the normal way Victor works — that is not an
    /// answer at all. The title an agent writes for itself is the one thing that
    /// tells them apart, and it is the half that keeps moving while it works, so
    /// a chip carrying it also says the session is alive. Truncated hard,
    /// because it rides beside the cursor over whatever he is reading and a
    /// title is the one part of this with no length anybody controls.
    private var identity: String {
        guard boundLabel != nil else { return "🤖 \(SessionLabel.value)" }
        // `walkie-talkie@main` — the working directory of the session the words are
        // going to, with its branch when that directory is a repo. The icon beside
        // it (`titleGlyph`) says which app, so this line never spells out an app
        // name it can show instead; only a target with no directory to read falls
        // back to one.
        return boundFolder ?? boundLabel ?? ""
    }

    // The title used to be borrowable for a moment (`flashTitle`, for the "+1 📸"
    // receipt). Nothing needs it now that F3 reports itself in the recording row,
    // and a title that can be temporarily untrue is worth removing while nothing
    // depends on it: this line's whole job is to say which session he is talking to.

    /// Fully opaque whenever it has something to say. The idle chip sits at 0.80:
    /// it now rides along near the cursor, over Victor's actual work, so it has
    /// to read as an overlay rather than as part of the page — but not so faint
    /// that the one thing it carries (which session it is) is hard to read.
    ///
    /// Paused keeps its 0.30: there, fading is the message. The relay is off, and
    /// the overlay looking switched off is the point.
    private func refreshOpacity() {
        // The chip belongs to the pointer: no pointer, no chip. Panels are their
        // own reason to be on screen and stay put.
        let target: CGFloat = (anchored && typing) ? 0.0
                            : paused ? 0.30
                            : (anchored ? 0.80 : 1.00)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = target
        }
    }

    // MARK: - Animations

    /// The 🔴 breathes while Wispr is listening, so the overlay visibly *lives* — a
    /// frozen recording row is indistinguishable from a hung app, and the whole
    /// point of the state is reassurance that speech is being caught.
    ///
    /// This is the job the trailing dots and the glass-shine sweep used to do.
    /// Both were built for the panel; the recording row rides on the bare chip
    /// now, where a sweep of glare has no glass to cross, and one slow pulse in
    /// peripheral vision says the same thing more quietly.
    ///
    /// Slow on purpose — 1.1s each way. Anything brisker turns a reassurance into
    /// something blinking beside the cursor while he is trying to think.
    private func startPulse() {
        stopPulse()
        guard let layer = recordDot.layer else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }

    private func stopPulse() { recordDot.layer?.removeAnimation(forKey: "pulse") }

    // MARK: - Public API (main thread)

    /// `count` is how many highlights this dictation is now carrying, the frozen
    /// one included. The row shows the **newest** and prefixes `×N` once there
    /// is more than one — the same reading `📸 ×N` and `🎯 ×N` already use, and
    /// for the same reason: what he can check at a glance is *that* the last
    /// gesture landed, and the running total is what says none of the earlier
    /// ones fell out. The row stays one line; a stack of them would push the
    /// chip over the work it is riding on.
    func setSelection(_ text: String?, count: Int = 1) {
        selection = (text?.isEmpty == false) ? text : nil
        selectionCount = selection == nil ? 0 : max(1, count)
        layoutContent()
    }

    func clearSelection() { setSelection(nil, count: 0) }

    /// The relay has been pointed at a terminal, or has lost the one it had.
    ///
    /// Relayouts because the title drives the chip's width, and a bound label is
    /// a different length from the launch-directory one it replaces.
    func setBound(label: String?, folder: String? = nil, icon: NSImage? = nil) {
        guard boundLabel != label || boundFolder != folder || boundIcon !== icon else { return }
        boundLabel = label
        boundFolder = label == nil ? nil : folder
        boundIcon = label == nil ? nil : icon
        titleGlyph.image = boundIcon ?? Self.pinGlyph
        refreshTitle()
        layoutContent()
    }

    /// The local recogniser is coming up (or going away). Drives the ⏳ on the
    /// chip; `StatusItem` shows the same thing in the menu bar, which is the half
    /// that is still visible while he types and the pointer — and with it the
    /// chip — is hidden.
    func setEngineLoading(_ value: Bool) {
        guard engineLoading != value else { return }
        engineLoading = value
        refreshTitle()
        layoutContent()
    }

    func setPaused(_ value: Bool) {
        paused = value
        refreshTitle()
        layoutContent()          // pausing mid-dictation retracts the recording row
        reposition()             // …and parks the panel back in its corner
    }

    /// The relay is recording through its own microphone (Local Whisper), rather
    /// than watching Wispr do it. Set around `setListening`, which stays the one
    /// switch for everything that is the same in both modes — the pulse, the row,
    /// the borrowed gestures.
    func setLocalListening(_ value: Bool) {
        guard localListening != value else { return }
        localListening = value
        layoutContent()
    }

    /// Take a banner down early — for one that was a promise ("transcribing…")
    /// rather than a notice, and has now been kept. Without this the promise
    /// outlives the thing it promised by however long its timer had left.
    func clearFlash() {
        guard flashMessage != nil else { return }
        flashMessage = nil
        layoutContent()
        reposition()
        refreshOpacity()
    }

    /// Wispr started / stopped listening.
    func setListening(_ value: Bool) {
        guard listening != value else { return }
        listening = value
        // The count belongs to one dictation. Zeroing it here rather than when the
        // message is sent means the row never opens showing the last dictation's
        // total for the split second before the first shot lands.
        if value { shotCount = 0 }
        refreshTitle()
        layoutContent()          // the recording row lives and dies with this state
        reposition()             // …and the chip snaps back to the cursor
        if value { startPulse() } else { stopPulse() }
    }

    /// How many pictures this dictation is carrying, the automatic context capture
    /// included — he took one picture by starting to talk and the rest with F3, and
    /// a count that omitted the first would disagree with what the agent receives.
    func setShotCount(_ count: Int) {
        guard shotCount != count else { return }
        shotCount = count
        layoutContent()          // the number can widen the row
    }

    /// How many elements are ⌘-picked and waiting, and what the newest one was.
    ///
    /// No `reposition()` here, unlike `setListening`: a pick happens while his
    /// hand is in Chrome, and yanking the chip back under the cursor mid-gesture
    /// would move something in the corner of his eye for no reason. The row
    /// simply appears where the chip already is.
    func setPicks(count: Int, newest: String?) {
        guard pickCount != count || pickNewest != newest else { return }
        pickCount = count
        pickNewest = newest
        layoutContent()
    }

    /// Show the prompt on its way to the agent, whole, so Victor can see exactly
    /// what Wispr heard — a mis-transcription is much cheaper to catch here than
    /// three tool calls later.
    ///
    /// The prompt is **held**, not already gone: for `hold` seconds it sits here
    /// with a Cancel button, and only then does it reach the outbox. That is what
    /// makes the button mean something — a prompt already written cannot be
    /// recalled, since the agent polls the queue every couple of seconds and may
    /// have started acting on it before Victor's hand reaches the mouse.
    ///
    /// Returns false if there was nothing worth showing, in which case the caller
    /// still owns the message and must release it itself.
    @discardableResult
    func showSentPrompt(_ text: String, hold: TimeInterval) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // A prompt still on screen has not been released yet. Let it go first, so
        // two dictations in quick succession reach the agent in the order spoken.
        resolvePrompt(send: true)

        sentPrompt = trimmed
        // The selection is already part of what is displayed here, so drop the
        // separate preview row rather than showing it twice.
        selection = nil
        promptDeadline = Date().addingTimeInterval(hold)
        updateCancelTitle()
        // Park first, then unfold: repositioning after an animated resize would
        // snap the window to its destination and eat the animation.
        reposition()
        layoutContent(animated: true)
        refreshOpacity()

        promptTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
            self?.resolvePrompt(send: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        promptTimer = timer

        // Four ticks a second: the number on the button should count down
        // smoothly rather than jump, since it is the only thing telling him
        // whether he still has time to reach for it.
        countdownTimer?.invalidate()
        let tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateCancelTitle()
        }
        RunLoop.main.add(tick, forMode: .common)
        countdownTimer = tick
        return true
    }

    private func updateCancelTitle() {
        guard let deadline = promptDeadline else { return }
        let left = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        sendButton.title = "⏎ Send \(left)s"
        cancelButton.title = "✕ Cancel"
    }

    /// The single exit from the displayed-prompt state: collapse back to the
    /// small overlay and tell the delegate whether to release the message or bin
    /// it. Fires once — every later call finds `sentPrompt` already nil.
    private func resolvePrompt(send: Bool) {
        guard sentPrompt != nil else { return }
        promptTimer?.invalidate()
        promptTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        promptDeadline = nil
        sentPrompt = nil
        layoutContent()
        reposition()
        refreshOpacity()
        // Last, and with the state already cleared: the delegate may well show
        // the next prompt from inside this call.
        onPromptResolved?(send)
    }

    /// Release anything still being held — used when the app is going away and
    /// the choice is between sending it now and losing it.
    func flushHeldPrompt() { resolvePrompt(send: true) }

    /// Transient status in the subtitle row — which it also *summons*, since at
    /// rest that row is not on screen at all.
    func flash(_ message: String, duration: TimeInterval = 2.0) {
        flashMessage = message
        layoutContent()
        reposition()             // still beside the pointer — a flash is not a reason to move
        refreshOpacity()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.flashMessage == message else { return }
            self.flashMessage = nil
            self.layoutContent()
            self.reposition()
            self.refreshOpacity()
        }
    }

    fileprivate func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        // No ✕ while it is trailing the cursor. There it is a label, not a
        // window: an end-session button on something that moves away as you
        // reach for it is a button that means nothing. It comes back with the
        // panel — during a dictation, and on the prompt.
        closeButton.isHidden = !value || anchored
        if value {
            // A hidden view gets no mouse events, so its tracking area is stale
            // by the time it is revealed — without this the ✕ never lights up.
            closeButton.updateTrackingAreas()
            closeButton.needsDisplay = true
        }
        refreshOpacity()
    }

    /// Draw the overlay into a PNG — the only way left to *see* it.
    ///
    /// The window is excluded from every screen capture (`sharingType`), and
    /// `RELAY_CAPTURABLE=1` no longer buys it back on macOS 15: `screencapture`
    /// returns a transparent image, whole-display or `-l <windowid>`. So instead
    /// of asking the window server for the pixels, ask the view to draw itself.
    /// `SIGUSR1` triggers it (see `AppDelegate`), which means any state can be
    /// photographed from a shell while it is on screen.
    ///
    /// What comes out is the content, not the composite: the blur behind a panel
    /// is drawn by the window server and is simply absent here, so panel shots
    /// land on transparency. The chip has no blur at all, so it comes out exactly
    /// as Victor sees it — over whatever you composite it onto.
    func snapshot(to path: String) {
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        Log.info("snapshot → \(path) (\(Int(root.bounds.width))×\(Int(root.bounds.height)))")
    }

    // MARK: - Hit handling (called from RelayView)

    /// No double-click to disambiguate any more, so a click acts immediately.
    ///
    /// While a prompt is up, clicking the overlay body means "yes, that's right,
    /// go" — it releases the message immediately instead of waiting out the
    /// countdown, and gets the wide panel off his work. The one place where a
    /// click means *no* is the Cancel button, which swallows its own clicks.
    /// Toggling pause here would be the mistake he would never notice.
    fileprivate func handleClick() {
        if sentPrompt != nil {
            resolvePrompt(send: true)
            return
        }
        onTogglePause?()
    }

    /// Dragging is a panel gesture. The chip is pinned to the cursor, so hauling
    /// it around would only mean fighting the thing that puts it back.
    fileprivate func beginDrag() { draggingSelf = !anchored }
    fileprivate func endDrag() { draggingSelf = false }

    fileprivate func moveBy(dx: CGFloat, dy: CGFloat) {
        guard draggingSelf else { return }
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }
}

// MARK: - Panel

final class RelayPanel: NSPanel {
    // The overlay has no text entry, so it must never take the caret away from
    // the app Victor is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit likes to pull windows back onto the screen. The chip is pinned to
    // the cursor, so at the right-hand edge that help is precisely wrong: it
    // would shove the label off its anchor to keep it whole.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - Close button

/// The round ✕ in the top-right, in the style of a macOS notification: hidden
/// until the pointer is over the overlay, then a grey disc with a dark cross.
final class CloseButton: NSView {
    var onClick: (() -> Void)?
    private var hot = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Dynamic system colours, resolved against `effectiveAppearance` at draw
        // time, so the button reads correctly in both light and dark mode:
        //   disc  = secondaryLabelColor — dark grey on light, light grey on dark
        //   cross = textBackgroundColor — the inverse of that in both modes
        // A hardcoded white cross looked fine on light mode's dark disc and
        // vanished against dark mode's light one.
        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        if hot {
            NSColor.systemRed.withAlphaComponent(0.90).setFill()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
        }
        disc.fill()

        let inset = bounds.width * 0.32
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset, y: inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        cross.move(to: NSPoint(x: inset, y: bounds.height - inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: inset))
        cross.lineWidth = 1.6
        cross.lineCapStyle = .round
        // On the red hover disc, white always wins in either appearance.
        (hot ? NSColor.white : NSColor.textBackgroundColor).withAlphaComponent(0.95).setStroke()
        cross.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hot = false; needsDisplay = true }

    // Swallow the whole click so it never reaches RelayView's pause handling.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
}

// MARK: - Cancel button

/// The button that stops a held prompt from ever reaching the agent.
///
/// Drawn rather than an `NSButton` because the overlay's panel never becomes key:
/// standard controls in a non-activating panel look permanently disabled and
/// swallow the first click activating the window. This one is always live.
final class PillButton: NSView {
    var onClick: (() -> Void)?
    /// What it looks like under the cursor. Red for the destructive one, the
    /// system accent for the one that simply does the expected thing sooner.
    var accent: NSColor = .systemRed
    var title: String = "" {
        didSet { guard title != oldValue else { return }; needsDisplay = true }
    }
    private var hot = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        // Red only under the cursor. At rest it is one more quiet control: the
        // overlay is on screen all day and a permanently red button reads as an
        // error rather than as an offer.
        if hot {
            accent.withAlphaComponent(0.92).setFill()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.22).setFill()
        }
        pill.fill()
        NSColor.secondaryLabelColor.withAlphaComponent(hot ? 0.0 : 0.35).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: hot ? NSColor.white : NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            in: NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height),
            withAttributes: attrs)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hot = false; needsDisplay = true }

    // Swallow the whole click — reaching RelayView would release the very
    // prompt this button exists to stop.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - Content view (drag + click)

final class RelayView: NSView {
    weak var owner: RelayWindow?
    var blur: NSVisualEffectView?

    private var dragOrigin: NSPoint?
    private var dragged = false

    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        dragged = false
        owner?.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if abs(dx) > 1 || abs(dy) > 1 { dragged = true }
        owner?.moveBy(dx: dx, dy: dy)
        dragOrigin = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil; owner?.endDrag() }
        guard !dragged else { return }     // a drag is not a click
        owner?.handleClick()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // .activeAlways: the overlay belongs to an accessory app that is never
        // frontmost, so .activeInActiveApp would never fire.
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { owner?.setHovering(true) }
    override func mouseExited(with event: NSEvent)  { owner?.setHovering(false) }
}
