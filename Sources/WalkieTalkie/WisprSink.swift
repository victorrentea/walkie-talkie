import AppKit
import ApplicationServices

/// **A window of this app's own that stands in for the app Victor is dictating
/// into** — so Wispr Flow inserts its sentence *here*, where the relay can read
/// it, instead of into his work where it cannot be taken back.
///
/// ## Why it exists, and what it is going to become
///
/// It was written on 2026-09-13 as a test instrument, and it is still only that
/// today: `POST /test/sink` opens it and nothing on a real dictation path calls
/// it. But it is built as a component rather than a throwaway window because
/// Victor's design is that it becomes **the wrapping mechanism**. His ask: only
/// Wispr's transcription engine, with Walkie giving Wispr its inputs and taking
/// its outputs synthetically, and Wispr never inserting into the real app at
/// all. Under that design the wrap stops being *swallow the ⌘V and hope* and
/// becomes *hold the focus, catch the insertion by whatever route it arrives,
/// hand the focus back, deliver the words ourselves*.
///
/// **The scope of that wrap is already decided and is narrow**: it applies only
/// to dictations *this app started* — the chord it posted itself, stamped
/// `backButtonStamp` — and only while the **Wrap Wispr Flow** tick is on. A
/// dictation Victor starts with his own keyboard shortcut is Wispr's and is
/// left alone; taking the focus off him for one of those would be the app
/// interfering with a tool he is using directly.
///
/// **What is not yet known, and is what the loop is for**: whether Wispr Flow
/// picks the app it will insert into at the *chord* or at *insertion time*. The
/// two give opposite instructions — hold the key window from the moment the
/// dictation opens, or take it only at the stop gesture and give it back a
/// moment later — and nothing in Wispr says which. `becomeKey()` and
/// `restoreFocus()` are separate calls, and `POST /test/sink {"key": true}` /
/// `{"restore": true}` drive them, precisely so a runner can measure both.
///
/// ## What it catches, and why the route matters
///
/// Two dictations went wrong on 2026-09-13 and both were *the words landed
/// somewhere else*. A 2.5 s dictation into Word produced no CoreAudio edge at
/// all, so the swallow window was never armed and Wispr's ⌘V went straight
/// through; a second forward click landed inside a settle, started a phantom
/// sentence, and that sentence's ⌘V landed in whatever Terminal was in front. In
/// neither case was there anything to read back afterwards.
///
/// So the text view is instrumented on all four routes text can reach a text
/// view by, and each one says its own name: `paste` (the ⌘V Wispr posts), `ax:…`
/// (an Accessibility write, named after whichever setter fired — this is how
/// Wispr inserted the two sentences that made `WisprHistory` necessary),
/// `typed` (an `insertText` that was not a paste), `keyDown` (raw). *Which*
/// route delivered is the whole point: it is the difference between a wrap that
/// works and one that waits out a timeout for a key that is never coming.
///
/// ## The focus exception
///
/// **This is the one deliberate exception to "nothing in it ever calls
/// `NSApp.activate`"** (CLAUDE.md, *Build, install, restart*). The rule is there
/// because a dictation helper that steals focus takes the caret away from the
/// work it is meant to be typing into — and being the caret is exactly what this
/// window has to do. So the exception is fenced rather than argued away: the
/// sink remembers the application that was frontmost (and, cheaply, the focused
/// element) before it takes the keyboard, and `restoreFocus()` puts both back.
/// Nothing outside a `POST` opens it today.
///
/// It is not a bindable terminal and cannot become one — `bindFrontmostTerminal`
/// asks Terminal, tmux and the two IDE bridges what is in front, and this window
/// belongs to none of them. `RelayWindow.snapshot` photographs `root` directly
/// and never enumerates the app's windows, so the sink cannot appear in
/// `docs/states/` either.
final class WisprSink {

    static let shared = WisprSink()

    /// One thing that arrived, and how.
    struct Event {
        let at: Date
        /// `paste`, `ax:<setter>`, `typed`, `keyDown`.
        let route: String
        let text: String
    }

    // MARK: - What it caught

    private(set) var events: [Event] = []
    /// Everything in the view right now.
    var text: String { view?.string ?? "" }

    /// **A sentence landed.** Called on the main thread, `arrivalDebounce` after
    /// the last insertion that belongs to it.
    ///
    /// Debounced rather than fired per insertion because two of the four routes
    /// arrive in pieces: an Accessibility write can be a selected-text replace
    /// followed by a value set, and a recogniser that *types* produces one call
    /// per character. A wrap that delivered on the first fragment would deliver
    /// a third of the sentence.
    var onArrival: ((_ text: String, _ route: String) -> Void)?

    /// 150 ms — long enough to gather a paste plus its trailing AX write, far
    /// short of anything a hand notices. Not measured against a typing
    /// recogniser, because no recogniser here types; raise it if one ever does.
    var arrivalDebounce: TimeInterval = 0.15

    private var pendingText: [String] = []
    private var pendingRoutes: [String] = []
    private var arrivalTimer: Timer?

    /// A runaway typist must not grow this without bound; a test that needs more
    /// than this many events is not asserting anything.
    private static let maxEvents = 500

    // MARK: - The window

    private var window: SinkWindow?
    private var view: SinkTextView?
    private lazy var closer = SinkWindowCloser(sink: self)

    var isOpen: Bool { window != nil }
    var isKey: Bool { window?.isKeyWindow ?? false }

    /// **Small, borderless, and in a corner** — the opposite of the 500×200 panel
    /// this started as. It has to be able to take the keyboard without being a
    /// visible panel over his work, because under the wrap it will be doing that
    /// during ordinary dictations. A borderless window can be any size at all;
    /// what it cannot be is *offscreen*, so it sits just inside the bottom-left
    /// of the visible frame rather than beyond it. 40×20 is the smallest that was
    /// tried and took key focus on this Mac; 1×1 was not risked for an instrument
    /// whose whole job is to hold focus reliably.
    private static let size = NSSize(width: 40, height: 20)
    private static let inset: CGFloat = 4

    /// Who had the keyboard before `becomeKey` took it.
    private var previousApp: NSRunningApplication?
    private var previousElement: AXUIElement?

    // MARK: - Open and close

    /// Main thread only. Opening also takes the keyboard — a sink nobody is
    /// typing into catches nothing — and `restoreFocus()` hands it straight back
    /// for the runner that wants to test the other hypothesis.
    func setOpen(_ on: Bool) { on ? open() : close() }

    func open() {
        if window == nil { build() }
        becomeKey()
    }

    private func build() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let frame = NSRect(x: area.minX + Self.inset, y: area.minY + Self.inset,
                           width: Self.size.width, height: Self.size.height)
        let w = SinkWindow(contentRect: frame, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        w.title = "Walkie sink"
        w.isReleasedWhenClosed = false
        w.hasShadow = false
        w.backgroundColor = .black
        w.alphaValue = 0.85
        // **A normal level, on purpose.** `.floating` would keep it over the work
        // and out of the way, which is the opposite of what it is for: the sink
        // has to be an ordinary key window, because the question it answers is
        // what an ordinary key window would have received.
        w.level = .normal
        w.delegate = closer

        let text = SinkTextView(frame: NSRect(origin: .zero, size: frame.size))
        text.owner = self
        text.isEditable = true
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        text.backgroundColor = .black
        text.textColor = .white
        text.autoresizingMask = [.width, .height]
        w.contentView = text

        window = w
        view = text
        Log.info("🧪 wispr sink open at \(Int(frame.minX)),\(Int(frame.minY)) — \(Int(frame.width))×\(Int(frame.height))")
    }

    func close() {
        guard let w = window else { return }
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        pendingText = []
        pendingRoutes = []
        restoreFocus()
        window = nil
        view = nil
        w.orderOut(nil)
        w.close()
        Log.info("🧪 wispr sink closed")
    }

    fileprivate func windowClosedItself() {
        window = nil
        view = nil
    }

    // MARK: - The keyboard, taken and given back

    /// **Take the keyboard, remembering whose it was.**
    ///
    /// The frontmost application is the half that matters and is free. The
    /// focused *element* is asked for as well because a restore that only
    /// re-activates the app puts the caret wherever that app last had it, which
    /// after a window switch is not where he left it — one `AXUIElementCopy
    /// AttributeValue` on the system-wide element, no traversal, is cheap enough
    /// to be worth it. Both are best-effort: a missing one is not an error, it
    /// just means the restore does less.
    func becomeKey() {
        guard let w = window else { return }
        if !isKey {
            // **Never this app** — recording ourselves would make `restoreFocus`
            // re-activate the sink it is meant to be letting go of, and the
            // window would still have the keyboard afterwards. The frontmost app
            // is already us whenever `becomeKey` is called twice, or called from
            // a menu row, and that is not a caret worth putting back.
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == getpid() ? nil : front
            previousElement = previousApp == nil ? nil : Self.focusedElement()
        }
        // The exception, in one line. See the note on the type.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        if let view { w.makeFirstResponder(view) }
        Log.info("🧪 wispr sink has the keyboard — it was \(previousApp?.localizedName ?? "nobody")'s")
    }

    /// **Give it back**, without closing: the wrap's second half, and the half a
    /// runner has to be able to fire on its own to tell the two timing
    /// hypotheses apart.
    func restoreFocus() {
        let app = previousApp
        let element = previousElement
        previousApp = nil
        previousElement = nil
        guard let app else {
            // **Nothing to go back to still has to stop being the caret.**
            // `NSApp.deactivate` hands the keyboard to whatever the system
            // decides is next without hiding anything — `NSApp.hide` would take
            // the chip and the halo down with it, which are the two things that
            // must stay on screen through a dictation.
            guard isOpen else { return }
            NSApp.deactivate()
            Log.info("🧪 wispr sink let the keyboard go — nobody had it before")
            return
        }
        app.activate(options: [])
        // Best-effort, and after the activation: setting `kAXFocused` on an
        // element of an app that is not frontmost is refused by most apps.
        if let element {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
        }
        Log.info("🧪 wispr sink gave the keyboard back to \(app.localizedName ?? "the last app")")
    }

    private static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success,
              let element = value else { return nil }
        return (element as! AXUIElement)
    }

    // MARK: - What arrived

    fileprivate func record(route: String, text: String) {
        guard !text.isEmpty else { return }
        events.append(Event(at: Date(), route: route, text: text))
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
        Log.info("🧪 wispr sink ← \(route): \(text.count) chars")

        pendingText.append(text)
        if pendingRoutes.last != route { pendingRoutes.append(route) }
        arrivalTimer?.invalidate()
        let t = Timer(timeInterval: arrivalDebounce, repeats: false) { [weak self] _ in
            self?.flushArrival()
        }
        arrivalTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func flushArrival() {
        arrivalTimer = nil
        let text = pendingText.joined()
        let route = pendingRoutes.joined(separator: "+")
        pendingText = []
        pendingRoutes = []
        guard !text.isEmpty else { return }
        Log.info("🧪 wispr sink: a sentence landed via \(route) — \(text.count) chars")
        onArrival?(text, route)
    }

    /// Main thread only.
    func clear() {
        events = []
        pendingText = []
        pendingRoutes = []
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        view?.string = ""
        Log.info("🧪 wispr sink cleared")
    }

    /// Main thread only — `GET /test/sink`.
    func describe() -> [String: Any] {
        ["open": isOpen,
         "key": isKey,
         "previousApp": previousApp?.localizedName ?? "",
         "text": text,
         "events": events.map { e -> [String: Any] in
             ["at": Outbox.iso(e.at), "route": e.route, "chars": e.text.count, "text": e.text]
         }]
    }
}

/// **Borderless windows do not take the keyboard unless they say they can.**
/// `canBecomeKey` is false by default for `.borderless`, which is exactly the
/// property that makes the overlay safe (`RelayPanel`) and exactly the one this
/// window has to give up.
private final class SinkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    /// Not main, though: the app's menu bar and its About window belong to the
    /// relay, and a 40×20 sink claiming to be the main window is a lie AppKit
    /// has no use for.
    override var canBecomeMain: Bool { false }
}

/// The window delegate, kept off `WisprSink` itself so the sink is not an
/// `NSObject` for one method's sake.
private final class SinkWindowCloser: NSObject, NSWindowDelegate {
    private weak var sink: WisprSink?
    init(sink: WisprSink) { self.sink = sink }
    func windowWillClose(_ notification: Notification) { sink?.windowClosedItself() }
}

/// **The four doors text can come through, each one named as it opens.**
///
/// `paste` is checked first and sets a flag, because a paste reaches
/// `insertText` too: without the flag every ⌘V would be reported twice, once
/// honestly and once as though Wispr had typed it.
private final class SinkTextView: NSTextView {

    weak var owner: WisprSink?
    private var pasting = false

    // MARK: ⌘V

    /// **The app has no Edit menu**, and a plain `NSTextView` gets ⌘V from the
    /// menu's key equivalent. `main.swift` installs the minimum a `.regular` app
    /// owes its menu bar — About, Hide, Quit — and nothing in it carries
    /// `paste:`, so without this the one route the sink exists to catch would
    /// arrive and do nothing at all, silently, which is the exact failure shape
    /// being tested for.
    ///
    /// Handled here rather than by installing an Edit menu while the sink is up:
    /// the menu bar is Victor's, and a route that works by changing the app's
    /// menus would be testing the menus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        pasting = true
        defer { pasting = false }
        super.paste(sender)
        owner?.record(route: "paste", text: text)
    }

    // MARK: Typed, and the raw key behind it

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard !pasting else { return }
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        owner?.record(route: "typed", text: text)
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        owner?.record(route: "keyDown", text: event.characters ?? "")
    }

    // MARK: The Accessibility writes

    /// **Which of these an external process actually lands on is the question**,
    /// so all three are implemented and each says its own name. An app setting
    /// `kAXSelectedText` on this view arrives at the first; one setting `kAXValue`
    /// at the second; anything still speaking the pre-10.10 protocol at the
    /// third. Wispr Flow inserted two sentences on 2026-09-12 by a route that
    /// left no ⌘V and no pasteboard change at all, and this is where that route
    /// finally has a name.
    override func setAccessibilitySelectedText(_ accessibilitySelectedText: String?) {
        super.setAccessibilitySelectedText(accessibilitySelectedText)
        owner?.record(route: "ax:selectedText", text: accessibilitySelectedText ?? "")
    }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        super.setAccessibilityValue(accessibilityValue)
        owner?.record(route: "ax:value",
                      text: (accessibilityValue as? String)
                          ?? (accessibilityValue as? NSAttributedString)?.string ?? "")
    }

    /// The pre-10.10 spelling, which returns nothing and is deprecated —
    /// overridden anyway, because *which* of these an external process lands on
    /// is exactly the unknown, and an app still speaking the old protocol would
    /// otherwise arrive here and be invisible. Marked deprecated itself so
    /// calling `super` does not warn: the override is deliberate.
    @available(macOS, deprecated: 10.10)
    override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
        super.accessibilitySetValue(value, forAttribute: attribute)
        let text = (value as? String) ?? (value as? NSAttributedString)?.string ?? ""
        owner?.record(route: "ax:\(attribute.rawValue)", text: text)
    }
}
