import AppKit
import WebKit

/// **The Gesture Guide: every gesture drawn on his own mouse, and played**
/// (2026-11-12, Victor: *"The Walkie Talkie menu is huge and useless. Rather than
/// having this endless list of gestures that are explained, prefer to have a page
/// to teach schematically the gestures. Starting from the image of the Logi mouse
/// I have. The sketch animated, what it feels trigger different gestures. Like a
/// user guide … in a window that shows when the user clicks the menu entry"*).
///
/// It replaced two things at once: the menu's legend rows with their one-glyph
/// chords, and the About panel (`AboutWindow`) that decoded those glyphs on a
/// still drawing. One page now teaches the gestures and says the build.
///
/// **A native panel holding a `WKWebView`**, not a page in the browser (the About
/// panel's 2026-09-22 rule: *"să fie nu webpage ci pagina swift"*) — the page is
/// only the drawing surface, because CSS keyframes animate twenty small scenes for
/// free where Core Animation would be a layer tree per card. Nothing is fetched:
/// the mouse pictures are `Glyphs.mouse` (traced off the Signature M650 L's
/// wireframe) rendered here to PNG and inlined, so the drawing is the one the chip
/// and the hint bar use.
///
/// **From above, nose up** (2026-11-12, Victor, on the first build's three-quarter
/// `mouseIso`: *"pare că îl muți cumva în spate … ori din spate reprezentat, ori de
/// sus"*): a swipe right on the page is the mouse moving right under his hand, a
/// swipe up is pushing it away. `guide: true` draws the wheel without the island it
/// sits in (*"ce reprezintă bara asta … e doar wheel-ul"*) and both thumb buttons on
/// the left flank always.
///
/// **Each scene is the gesture itself**: the button you hold turns red, the mouse
/// moves the way you swipe, a ring marks a click. **A normal window, not floating**
/// (same evening: *"să nu mai stea on top"*) — a guide is read beside the work. The texts are the Logi set
/// (`mouse-gestures.md`, *Logi mode*); with *Gestures: Wheel* ticked a banner says
/// the side buttons are off. A gesture that changes in `HotkeyTap` changes here
/// by hand — this table is the page's, as the menu's legends were the menu's.
enum GestureGuide {

    /// Which vocabulary is live — `StatusItem` publishes it at launch and on the
    /// tick; `GestureHintBar` reads it too.
    static var logiGesturesOn = true

    enum Anchor { case top, about }

    private static var panel: NSPanel?
    private static var web: WKWebView?
    private static let loader = Loader()
    private static var loaded = false
    private static var pendingAnchor: Anchor = .top

    /// Up, or brought forward, without activating the app — the bound terminal
    /// keeps the keyboard (`.nonactivatingPanel`, `orderFrontRegardless`).
    static func show(at anchor: Anchor = .top) {
        if let p = panel, let w = web {
            w.loadHTMLString(page(), baseURL: nil)   // the vocabulary may have changed
            loaded = false
            pendingAnchor = anchor
            p.orderFrontRegardless()
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1040, screen.width - 80), height: min(860, screen.height - 60))
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Walkie Talkie — Gesture Guide"
        p.isFloatingPanel = false
        p.level = .normal
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 560, height: 420)

        let config = WKWebViewConfiguration()
        let w = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        w.autoresizingMask = [.width, .height]
        w.navigationDelegate = loader
        w.setValue(false, forKey: "drawsBackground")
        p.contentView = w
        panel = p
        web = w
        pendingAnchor = anchor
        loaded = false
        w.loadHTMLString(page(), baseURL: nil)
        p.center()
        p.orderFrontRegardless()
        Log.info("→ gesture guide \(Int(p.frame.width))×\(Int(p.frame.height))")
    }

    /// `POST /test/about` — the window server's own numbers and whether the page
    /// finished loading, never the layout's intent.
    static func describe() -> [String: Any] {
        // Opened if it is not up; left alone if it is, so a second call can
        // read whether the page has loaded.
        if panel?.isVisible != true { show() }
        guard let p = panel else { return ["shown": false] }
        return ["shown": p.isVisible,
                "window": p.windowNumber,
                "frame": ["x": p.frame.minX, "y": p.frame.minY, "w": p.frame.width, "h": p.frame.height],
                "loaded": loaded,
                "cards": cards.count,
                "vocabulary": logiGesturesOn ? "Logi" : "Wheel"]
    }

    /// Links leave for the browser; the page itself never navigates.
    private final class Loader: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            GestureGuide.loaded = true
            if GestureGuide.pendingAnchor == .about {
                webView.evaluateJavaScript("document.getElementById('about').scrollIntoView()")
            }
        }
    }

    // MARK: - The mouse, as pictures

    /// `Glyphs.mouse` (from above, `guide: true`) with the named buttons red, as a 2× PNG data URI. The body
    /// is a mid grey so one picture reads on both the light and the dark page.
    /// **One `<i>` per picture, the PNG once per page** — a class per pressed
    /// state, its data URI written into the style sheet once (`pictureCSS`).
    /// Inlined per card, the same picture made the page 2 MB.
    private static func mouse(_ pressed: Glyphs.Buttons, _ cls: String = "") -> String {
        _ = mouseURI(pressed)
        return "<i class=\"mi mi\(pressed.rawValue) \(cls)\"></i>"
    }

    private static func pictureCSS() -> String {
        mouseCache.sorted { $0.key < $1.key }
            .map { ".mi\($0.key) { background-image:url(\($0.value)) }" }.joined(separator: "\n")
    }

    private static func mouseURI(_ pressed: Glyphs.Buttons) -> String {
        if let hit = mouseCache[pressed.rawValue] { return hit }
        let height: CGFloat = 260
        var out = ""
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            let img = Glyphs.mouse(height: height, pressed: pressed,
                                   body: NSColor(white: 0.50, alpha: 1), highlight: .systemRed, guide: true)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                             pixelsWide: Int(img.size.width * 2), pixelsHigh: Int(img.size.height * 2),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = img.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(origin: .zero, size: img.size))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                out = "data:image/png;base64," + png.base64EncodedString()
            }
        }
        mouseCache[pressed.rawValue] = out
        return out
    }
    private static var mouseCache: [Int: String] = [:]

    /// Where each button sits on the top view, as fractions of its box (x right,
    /// y down from the nose) — the centres of the parts `Glyphs.mouse` draws.
    private static func spot(_ b: Glyphs.Buttons) -> (x: Double, y: Double) {
        switch b {
        case .forward: return (0.065, 0.392)
        case .back: return (0.109, 0.525)
        case .wheel: return (0.502, 0.217)
        case .left: return (0.290, 0.290)
        case .right: return (0.710, 0.290)
        default: return (0.5, 0.5)
        }
    }

    // MARK: - The gestures

    private enum Dir: String { case right, left, up, down }

    private enum Scene {
        /// Click a button.
        case click(Glyphs.Buttons)
        /// Hold a button and move the mouse.
        case swipe(Glyphs.Buttons, Dir)
        /// Hold one button, then click another.
        case holdClick(held: Glyphs.Buttons, click: Glyphs.Buttons)
        /// Hold the wheel and drag a box.
        case drag
        /// Hold keys, click the left button (in Chrome).
        case keysClick([String])
        /// Keys only: `hold` are held, `tap` pressed in the middle; `twice` taps twice.
        case keys(hold: [String], tap: [String], twice: Bool)
        /// Left ⌃⌥⌘ held, fingers on the trackpad.
        case trackpad(fingers: Int)
        /// A spoken phrase.
        case voice(String)
    }

    private struct Card {
        let section: String
        let title: String
        let chord: String
        let scene: Scene
        /// One line each; a leading `label:` is set in bold.
        let lines: [String]
    }

    private static let sections: [(id: String, title: String, lede: String)] = [
        ("forward", "Forward button — prompts",
         "An agent gets your words, a screenshot of the screen and anything you highlighted or picked."),
        ("back", "Back button — plain dictation",
         "Just your words, typed where the caret is. No picture, no envelope."),
        ("pictures", "While a prompt records — show it something",
         "Everything you point at lands in the prompt, at the moment you said it."),
        ("keyboard", "Keyboard", "For when the mouse is not in your hand."),
        ("trackpad", "Trackpad — no mouse attached",
         "Hold the left ⌃⌥⌘ and use the trackpad: one finger is the Forward button, two fingers the Back button."),
        ("voice", "Voice", "With 👂 Hey Claude ticked in the menu."),
    ]

    private static let cards: [Card] = [
        Card(section: "forward", title: "Prompt at the caret", chord: "Forward click",
             scene: .click(.forward),
             lines: ["Talk, then click Forward again to end it.",
                     "Pasted where you type — and sent, when the caret is in a Claude Code prompt."]),
        Card(section: "forward", title: "Prompt to the bound terminal", chord: "Hold Forward, swipe right",
             scene: .swipe(.forward, .right),
             lines: ["Ends with a Forward click.",
                     "Mid-sentence: flips the destination, bound terminal ⇄ caret.",
                     "Over a reply pop-up: answer the agent that sent it."]),
        Card(section: "forward", title: "Prompt to a new Claude session", chord: "Hold Forward, swipe up",
             scene: .swipe(.forward, .up),
             lines: ["A new Claude Code session opens with your words."]),
        Card(section: "forward", title: "Cancel — or ask ⚡", chord: "Hold Forward, swipe left",
             scene: .swipe(.forward, .left),
             lines: ["While dictating: throw the take away.",
                     "At rest: a quick question, answered in a pop-up beside the pointer."]),
        Card(section: "forward", title: "Kamikaze", chord: "Hold Forward, swipe down",
             scene: .swipe(.forward, .down),
             lines: ["While dictating: the agent closes its terminal when it is done.",
                     "Over a ⚡ question: Google it and answer it."]),
        Card(section: "forward", title: "Bind and prompt", chord: "Hold Left, click Forward",
             scene: .holdClick(held: .left, click: .forward),
             lines: ["Binds the terminal in front and opens a prompt to it."]),

        Card(section: "back", title: "Dictate, then Return", chord: "Back click",
             scene: .click(.back),
             lines: ["Click to start, click to stop: the words are typed, then Return.",
                     "While a prompt records: the shutter — one screenshot."]),
        Card(section: "back", title: "Dictate, no Return", chord: "Hold Back, swipe right",
             scene: .swipe(.back, .right),
             lines: ["Start or stop; only the words, at the caret.",
                     "Over a ⚡ question: Google it."]),
        Card(section: "back", title: "Stop — type — unbind", chord: "Hold Back, swipe down",
             scene: .swipe(.back, .down),
             lines: ["Plain dictation: stop it, no Return.",
                     "Prompt: open a box to type into.",
                     "At rest: let go of the bound terminal."]),
        Card(section: "back", title: "Cancel — or Return", chord: "Hold Back, swipe left",
             scene: .swipe(.back, .left),
             lines: ["Microphone open: cancel it.", "At rest: press Return."]),
        Card(section: "back", title: "Record the screen", chord: "Hold Back, swipe up",
             scene: .swipe(.back, .up),
             lines: ["While dictating: start or stop a screen recording for the prompt.",
                     "While it records, a Back click stops it."]),

        Card(section: "pictures", title: "Screenshot", chord: "Back click",
             scene: .click(.back),
             lines: ["One picture of the screen, placed in the words where you clicked."]),
        Card(section: "pictures", title: "Cut out an area", chord: "Hold the wheel, drag",
             scene: .drag,
             lines: ["Drag a box: only that area is attached."]),
        Card(section: "pictures", title: "Pick from a web page", chord: "Hold ⌘⇧, click in Chrome",
             scene: .keysClick(["⌘", "⇧"]),
             lines: ["The element under the pointer — its text and where it is."]),

        Card(section: "keyboard", title: "Plain dictation", chord: "Right ⌘ twice",
             scene: .keys(hold: [], tap: ["right ⌘"], twice: true),
             lines: ["Start; again to stop. The keyboard's only way to dictate."]),
        Card(section: "keyboard", title: "Bind the terminal in front", chord: "⌘⌃B",
             scene: .keys(hold: ["⌃", "⌘"], tap: ["B"], twice: false),
             lines: ["Again on the bound one: unbind."]),
        Card(section: "keyboard", title: "Transcribe on this Mac now", chord: "⌘⌃X",
             scene: .keys(hold: ["⌃", "⌘"], tap: ["X"], twice: false),
             lines: ["While recording or waiting on the cloud: the local model takes the take."]),
        Card(section: "keyboard", title: "Screenshot / make it a prompt", chord: "⌃P",
             scene: .keys(hold: ["⌃"], tap: ["P"], twice: false),
             lines: ["While a prompt records: the shutter.",
                     "Over a plain dictation: turns it into a prompt."]),

        Card(section: "trackpad", title: "One finger = Forward", chord: "Left ⌃⌥⌘ + one finger",
             scene: .trackpad(fingers: 1),
             lines: ["Click = Forward click; swipe ← → ↑ ↓ = Forward and that swipe."]),
        Card(section: "trackpad", title: "Two fingers = Back", chord: "Left ⌃⌥⌘ + two fingers",
             scene: .trackpad(fingers: 2),
             lines: ["Secondary click = Back click; swipe ← → ↑ ↓ = Back and that swipe."]),

        Card(section: "voice", title: "Start a new session", chord: "\u{201C}Hey Claude, …\u{201D}",
             scene: .voice("Hey Claude, fix the failing test"),
             lines: ["Say the task after it; a new Claude Code session gets it when you stop talking."]),
        Card(section: "voice", title: "Ask a quick question", chord: "\u{201C}Hey Claude, I have a question …\u{201D}",
             scene: .voice("Hey Claude, I have a question…"),
             lines: ["Answered in the ⚡ pop-up beside the pointer."]),
    ]

    // MARK: - The page

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func mouseStage(_ scene: Scene) -> String {
        var layers = ""
        var moveClass = ""
        var extra = ""
        func ripple(_ b: Glyphs.Buttons, _ cls: String) -> String {
            let s = spot(b)
            return "<span class=\"ripple \(cls)\" style=\"left:\(s.x * 100)%;top:\(s.y * 100)%\"></span>"
        }
        switch scene {
        case .click(let b):
            layers = mouse(b, "layer a-click") + ripple(b, "r-click")
        case .swipe(let b, let dir):
            layers = mouse(b, "layer a-hold")
            moveClass = "m-\(dir.rawValue)"
            extra = arrow(dir)
        case .holdClick(let held, let click):
            layers = mouse(held, "layer a-hold") + mouse([held, click], "layer a-click") + ripple(click, "r-click")
        case .drag:
            let s = spot(.wheel)
            layers = mouse(.wheel, "layer a-hold")
            moveClass = "m-drag"
            extra = "<span class=\"box\" style=\"--sx:\(s.x);--sy:\(s.y)\"></span>"
        case .keysClick(let keys):
            layers = mouse(.left, "layer a-click") + ripple(.left, "r-click")
            extra = "<div class=\"keys over\">" + keys.map { "<kbd class=\"k-hold\">\(esc($0))</kbd>" }.joined() + "</div>"
                + "<span class=\"element\"></span>"
        default:
            break
        }
        return """
        <div class="stage">\(extra)<div class="mouse \(moveClass)">\(mouse([]))\(layers)</div></div>
        """
    }

    private static func arrow(_ dir: Dir) -> String {
        // A dashed track in the direction of the swipe, drawn as the mouse travels.
        let (x1, y1, x2, y2): (Int, Int, Int, Int)
        switch dir {
        case .right: (x1, y1, x2, y2) = (70, 212, 200, 212)
        case .left: (x1, y1, x2, y2) = (170, 212, 40, 212)
        case .up: (x1, y1, x2, y2) = (204, 180, 204, 26)
        case .down: (x1, y1, x2, y2) = (204, 44, 204, 198)
        }
        return """
        <svg class="track" viewBox="0 0 240 224" aria-hidden="true"><defs><marker id="h\(dir.rawValue)" markerWidth="8" markerHeight="8" refX="5" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="currentColor"/></marker></defs><line class="t-line" x1="\(x1)" y1="\(y1)" x2="\(x2)" y2="\(y2)" marker-end="url(#h\(dir.rawValue))"/></svg>
        """
    }

    private static func stage(_ scene: Scene) -> String {
        switch scene {
        case .keys(let hold, let tap, let twice):
            let caps = hold.map { "<kbd class=\"k-hold\">\(esc($0))</kbd>" }
                + tap.map { "<kbd class=\"\(twice ? "k-twice" : "k-tap")\">\(esc($0))</kbd>" }
            return "<div class=\"stage keystage\"><div class=\"keys\">\(caps.joined(separator: "<span class=\"plus\">+</span>"))</div></div>"
        case .trackpad(let fingers):
            let dots = (0..<fingers).map { "<span class=\"finger\" style=\"--i:\($0)\"></span>" }.joined()
            return """
            <div class="stage padstage"><div class="keys small"><kbd class="k-hold">⌃</kbd><kbd class="k-hold">⌥</kbd><kbd class="k-hold">⌘</kbd></div><div class="pad"><div class="fingers f\(fingers)">\(dots)</div></div></div>
            """
        case .voice(let phrase):
            return "<div class=\"stage voicestage\"><div class=\"bubble\">\(esc(phrase))</div></div>"
        default:
            return mouseStage(scene)
        }
    }

    private static func card(_ c: Card) -> String {
        let lines = c.lines.map { "<li>\(esc($0))</li>" }.joined()
        return """
        <article class="card">\(stage(c.scene))<div class="text"><h3>\(esc(c.title))</h3><p class="chord">\(esc(c.chord))</p><ul>\(lines)</ul></div></article>
        """
    }

    private static func hero() -> String {
        let labels: [(Glyphs.Buttons, String, String)] = [
            (.forward, "Forward", "prompts"),
            (.back, "Back", "plain dictation"),
            (.wheel, "Wheel", "drag to cut out"),
            (.left, "Left", "held: bind"),
        ]
        let pins = labels.enumerated().map { i, l in
            let s = spot(l.0)
            return "<span class=\"pin\" style=\"left:\(s.x * 100)%;top:\(s.y * 100)%\">\(i + 1)</span>"
        }.joined()
        let legend = labels.enumerated().map { i, l in
            "<li><span class=\"pin static\">\(i + 1)</span><b>\(l.1)</b> — \(esc(l.2))</li>"
        }.joined()
        return """
        <section class="hero"><div class="heromouse">\(mouse([]))\(pins)</div>
        <div class="herotext"><h1>Gesture Guide</h1><p>Your <b>Logitech Signature M650 L</b>. The two thumb buttons do the work:
        <b>click</b> one, or <b>hold it and move the mouse</b> — the direction picks the gesture.</p>
        <ol class="legend">\(legend)</ol>
        <p class="how"><span class="redchip"></span> red = the button you press &nbsp;·&nbsp; the mouse slides the way you swipe</p></div></section>
        """
    }

    static func page() -> String {
        let banner = logiGesturesOn ? "" : """
        <div class="banner">The menu has <b>Gestures: Wheel</b> ticked — the side-button gestures below are off until you switch back to <b>Logi</b>.</div>
        """
        let body = sections.map { s in
            let items = cards.filter { $0.section == s.id }.map(card).joined()
            return "<section class=\"group\" id=\"\(s.id)\"><h2>\(esc(s.title))</h2><p class=\"lede\">\(esc(s.lede))</p><div class=\"grid\">\(items)</div></section>"
        }.joined()
        let about = """
        <footer id="about"><b>Victor's Walkie Talkie</b> · built \(esc(StatusItem.buildStamp)) ·
        <a href="https://github.com/victorrentea/walkie-talkie">github.com/victorrentea/walkie-talkie</a></footer>
        """
        let content = hero() + banner + body + about
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>Gesture Guide</title><style>\(css)\n\(pictureCSS())</style></head><body>"
            + content + "</body></html>"
    }

    private static let css = #"""
    :root { --bg:#f6f5f2; --card:#ffffff; --ink:#1d1d1f; --mute:#6e6e73; --line:#e3e1dc; --red:#e5372b;
            --track:#9a9aa0; --key:#ffffff; --keyline:#c9c7c2; --accent:#0a6cdb; color-scheme: light dark; }
    @media (prefers-color-scheme: dark) {
      :root { --bg:#1c1c1e; --card:#2a2a2d; --ink:#f2f2f4; --mute:#a1a1a6; --line:#3a3a3d; --red:#ff5246;
              --track:#7d7d84; --key:#3a3a3e; --keyline:#55555a; --accent:#5aa9ff; }
    }
    * { box-sizing:border-box; }
    html, body { margin:0; background:var(--bg); color:var(--ink);
                 font:14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
    body { padding:28px 32px 40px; }
    h1 { font-size:28px; margin:0 0 8px; letter-spacing:-0.02em; }
    h2 { font-size:18px; margin:0 0 2px; }
    h3 { font-size:15px; margin:0 0 2px; }
    .hero { display:flex; gap:36px; align-items:center; margin-bottom:22px; flex-wrap:wrap; }
    .heromouse { position:relative; width:148px; height:260px; flex:none; margin-left:40px; }
    .mi { position:absolute; inset:0; background:center / contain no-repeat; }
    .herotext { flex:1; min-width:260px; max-width:520px; }
    .herotext p { margin:0 0 10px; color:var(--mute); }
    .herotext b { color:var(--ink); }
    .pin { position:absolute; transform:translate(-50%,-50%); width:22px; height:22px; border-radius:50%;
           background:var(--ink); color:var(--bg); font:600 12px/22px -apple-system, sans-serif; text-align:center;
           box-shadow:0 0 0 3px var(--bg); }
    .pin.static { position:static; display:inline-block; transform:none; margin-right:8px; box-shadow:none; vertical-align:middle; }
    .legend { list-style:none; padding:0; margin:0 0 10px; display:grid; grid-template-columns:repeat(2, minmax(0,1fr)); gap:6px 18px; }
    .legend li { white-space:nowrap; }
    .how { font-size:12.5px; }
    .redchip { display:inline-block; width:10px; height:10px; border-radius:3px; background:var(--red); vertical-align:-1px; }
    .banner { border:1px solid var(--red); color:var(--ink); border-radius:10px; padding:10px 14px; margin:0 0 18px; }
    .group { margin-top:26px; }
    .lede { margin:0 0 12px; color:var(--mute); }
    .grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(300px, 1fr)); gap:14px; }
    .card { background:var(--card); border:1px solid var(--line); border-radius:14px; overflow:hidden; display:flex; flex-direction:column; }
    .text { padding:10px 14px 12px; border-top:1px solid var(--line); }
    .chord { margin:0 0 6px; color:var(--accent); font-weight:600; font-size:13px; }
    .text ul { margin:0; padding-left:16px; color:var(--mute); font-size:13px; }
    .text li { margin:1px 0; }
    footer { margin-top:34px; padding-top:14px; border-top:1px solid var(--line); color:var(--mute); font-size:12.5px; }
    a { color:var(--accent); text-decoration:none; }

    /* ── the stage: one gesture, looping every 3.2 s ── */
    .stage { position:relative; height:224px; overflow:hidden; --mw:88px; --mh:155px; }
    .mouse { position:absolute; left:50%; top:50%; width:var(--mw); height:var(--mh);
             margin:calc(var(--mh) / -2) 0 0 calc(var(--mw) / -2); }
    .layer { opacity:0; }
    .a-hold { animation:hold 3.2s infinite; }
    .a-click { animation:click 3.2s infinite; }
    .ripple { position:absolute; width:16px; height:16px; margin:-8px 0 0 -8px; border-radius:50%;
              border:2px solid var(--red); opacity:0; }
    .r-click { animation:ripple 3.2s infinite; }
    @keyframes hold  { 0%,14% { opacity:0 } 18%,72% { opacity:1 } 76%,100% { opacity:0 } }
    @keyframes click { 0%,36% { opacity:0 } 38%,50% { opacity:1 } 52%,100% { opacity:0 } }
    @keyframes ripple { 0%,37% { opacity:0; transform:scale(.4) } 40% { opacity:1 } 62%,100% { opacity:0; transform:scale(2.6) } }
    .m-right { animation:mright 3.2s infinite ease-in-out; }
    .m-left  { animation:mleft 3.2s infinite ease-in-out; }
    .m-up    { animation:mup 3.2s infinite ease-in-out; }
    .m-down  { animation:mdown 3.2s infinite ease-in-out; }
    .m-drag  { animation:mdrag 3.2s infinite ease-in-out; }
    @keyframes mright { 0%,22% { transform:none; opacity:1 } 56%,74% { transform:translateX(58px); opacity:1 }
                        82% { transform:translateX(58px); opacity:0 } 84% { transform:none; opacity:0 } 94%,100% { transform:none; opacity:1 } }
    @keyframes mleft  { 0%,22% { transform:none; opacity:1 } 56%,74% { transform:translateX(-58px); opacity:1 }
                        82% { transform:translateX(-58px); opacity:0 } 84% { transform:none; opacity:0 } 94%,100% { transform:none; opacity:1 } }
    @keyframes mup    { 0%,22% { transform:none; opacity:1 } 56%,74% { transform:translateY(-30px); opacity:1 }
                        82% { transform:translateY(-30px); opacity:0 } 84% { transform:none; opacity:0 } 94%,100% { transform:none; opacity:1 } }
    @keyframes mdown  { 0%,22% { transform:none; opacity:1 } 56%,74% { transform:translateY(30px); opacity:1 }
                        82% { transform:translateY(30px); opacity:0 } 84% { transform:none; opacity:0 } 94%,100% { transform:none; opacity:1 } }
    @keyframes mdrag  { 0%,22% { transform:none; opacity:1 } 56%,74% { transform:translate(50px,30px); opacity:1 }
                        82% { transform:translate(50px,30px); opacity:0 } 84% { transform:none; opacity:0 } 94%,100% { transform:none; opacity:1 } }
    .track { position:absolute; inset:0; width:100%; height:100%; color:var(--track); }
    .t-line { stroke:currentColor; stroke-width:2.5; stroke-dasharray:6 6; fill:none; animation:track 3.2s infinite; }
    @keyframes track { 0%,20% { opacity:0 } 30%,74% { opacity:1 } 84%,100% { opacity:0 } }
    /* the area being cut: anchored where the wheel starts, grows as the mouse drags */
    .box { position:absolute; left:calc(50% - var(--mw) / 2 + var(--mw) * var(--sx)); top:calc(50% - var(--mh) / 2 + var(--mh) * var(--sy));
           border:2px dashed var(--red); background:color-mix(in srgb, var(--red) 12%, transparent);
           width:0; height:0; animation:box 3.2s infinite ease-in-out; }
    @keyframes box { 0%,22% { width:0; height:0; opacity:1 } 56%,74% { width:50px; height:30px; opacity:1 }
                     82% { width:50px; height:30px; opacity:0 } 84%,100% { width:0; height:0; opacity:0 } }
    .element { position:absolute; left:14px; top:150px; width:70px; height:34px; border:2px solid var(--accent);
               border-radius:6px; opacity:0; animation:element 3.2s infinite; }
    @keyframes element { 0%,38% { opacity:0 } 42%,80% { opacity:1 } 86%,100% { opacity:0 } }

    /* keys */
    .keys { display:flex; align-items:center; justify-content:center; gap:6px; height:100%; }
    .keys.over { position:absolute; top:10px; left:0; right:0; height:auto; }
    .keys.small { height:auto; margin-top:12px; }
    .plus { color:var(--mute); font-weight:600; }
    kbd { min-width:38px; height:38px; padding:0 10px; display:inline-flex; align-items:center; justify-content:center;
          font:600 15px -apple-system, sans-serif; color:var(--ink); background:var(--key); border:1px solid var(--keyline);
          border-radius:8px; box-shadow:0 3px 0 var(--keyline); }
    .keys.over kbd, .keys.small kbd { min-width:30px; height:30px; font-size:13px; }
    .k-hold  { animation:khold 3.2s infinite; }
    .k-tap   { animation:ktap 3.2s infinite; }
    .k-twice { animation:ktwice 3.2s infinite; }
    @keyframes khold  { 0%,14% { transform:none; box-shadow:0 3px 0 var(--keyline); background:var(--key) }
                        18%,72% { transform:translateY(3px); box-shadow:0 0 0 var(--keyline); background:color-mix(in srgb, var(--red) 22%, var(--key)) }
                        76%,100% { transform:none; box-shadow:0 3px 0 var(--keyline); background:var(--key) } }
    @keyframes ktap   { 0%,36% { transform:none; box-shadow:0 3px 0 var(--keyline); background:var(--key) }
                        38%,52% { transform:translateY(3px); box-shadow:0 0 0 var(--keyline); background:color-mix(in srgb, var(--red) 35%, var(--key)) }
                        54%,100% { transform:none; box-shadow:0 3px 0 var(--keyline); background:var(--key) } }
    @keyframes ktwice { 0%,26%,36%,44%,54%,100% { transform:none; box-shadow:0 3px 0 var(--keyline); background:var(--key) }
                        28%,34%,46%,52% { transform:translateY(3px); box-shadow:0 0 0 var(--keyline); background:color-mix(in srgb, var(--red) 35%, var(--key)) } }

    /* trackpad */
    .padstage { display:flex; flex-direction:column; align-items:center; }
    .pad { position:relative; width:170px; height:88px; margin-top:8px; border:1.5px solid var(--keyline);
           border-radius:10px; background:color-mix(in srgb, var(--key) 70%, transparent); overflow:hidden; }
    .fingers { position:absolute; left:46px; top:30px; animation:mright 3.2s infinite ease-in-out; }
    .finger { position:absolute; left:calc(var(--i) * 22px); top:0; width:18px; height:22px; border-radius:50%;
              background:color-mix(in srgb, var(--red) 70%, transparent); animation:hold 3.2s infinite; opacity:0; }

    /* voice */
    .voicestage { display:flex; align-items:center; justify-content:center; }
    .bubble { position:relative; max-width:80%; padding:10px 14px; border-radius:16px; background:var(--accent); color:#fff;
              font-size:14px; overflow:hidden; white-space:nowrap; animation:say 3.2s infinite steps(28, end); }
    @keyframes say { 0% { clip-path:inset(0 100% 0 0) } 70%,100% { clip-path:inset(0 0 0 0) } }

    @media (prefers-reduced-motion: reduce) { * { animation-duration:0s !important; animation-iteration-count:1 !important; } }
    """#
}
