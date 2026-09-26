import AppKit

/// **The live caption as a film subtitle across the top of the screen**
/// (2026-09-26). Victor: *"pui subtitrarea live pe o bandă de înălțime 80 px pe
/// partea de sus a ecranului ca o subtitrare. font alb cu bordură/shadow negru
/// … ideal textul să se miște uniform smooth de la dreapta spre stânga, în ciuda
/// cuvintelor din transcriere care se modifică live … ochiul să urmărească lin
/// textul. Îl scoți așadar din tooltip."*
///
/// One borderless, click-through panel, `bandHeight` tall, pinned to the top
/// of the screen the pointer was on when the sentence began — under the menu
/// bar, so neither covers the other. No backdrop: white text with a black
/// outline and a soft shadow reads on a terminal and on a white page alike.
///
/// **The motion, not the words, is the design.** The recogniser hands over the
/// whole sentence as it has it now, about once a second, and the tail keeps
/// being revised. Anchoring the line at its *first* word and moving that anchor
/// means a revision only redraws the glyphs at the right end: everything
/// already on screen keeps its place. **The visible text stays centred**
/// (Victor, 2026-09-26 07:50: *"the visible text remains ~centered at all
/// times"*): the first words appear in the middle of the band, fading in; new
/// words are added on the right, fading in; when the eraser stings words out
/// on the left the rest re-centres. The anchor eases toward the centred
/// position elastically (`ease`, capped at `vMax`), so nothing ever steps.
/// A line wider than the band keeps its newest words inside the right margin
/// and lets the oldest leave on the left. Words fully gone — erased or off the
/// left edge — are dropped by advancing the anchor by exactly their width.
final class LiveCaptionBand {

    static let bandHeight: CGFloat = 80
    /// Where the line's end wants to be when he pauses: this far from the
    /// right edge. Inside the band, so the last word is always readable.
    private static let marginRight: CGFloat = 48
    /// A new line enters from the right edge and the first drop from the left
    /// happens this far past it, so nothing is dropped while still fading in.
    private static let dropSlack: CGFloat = 40
    private static let fontSize: CGFloat = 38

    private static let vMax: CGFloat = 700
    /// **Elastic, not a ramp** (Victor, 2026-09-26: *"o mișcare elastică
    /// blândă"*): the speed approaches its target exponentially with this time
    /// constant, so a burst of words is taken up as a gentle pull, never a
    /// kick, and a pause lets the line ease to rest.
    private static let ease: CGFloat = 0.45
    /// **A replacement is a swap in three overlapping beats** (Victor,
    /// 2026-09-26): the old words fade out over the first half of `swap`, the
    /// rest of the line glides elastically to make room (`reflow`), and the
    /// new words fade in over the second half — *"fadeout + fadein = durata
    /// glisare text în noua poziție"*. Once in, a new word is a faded yellow
    /// that returns to white over `correctionFade`.
    static let swap: CFTimeInterval = 1.0
    static let correctionFade: CFTimeInterval = 1.6
    /// The glide's time constant: 95 % of the way in three of these ≈ `swap`.
    static let reflow: CGFloat = 0.26
    /// **The segment still being spoken is provisional and looks it** (Victor,
    /// 2026-09-26: *"faded progresiv in"*): its words are drawn from this
    /// opacity at the newest up to solid at the committed boundary, and each
    /// word brightens (τ `reflow`) as the boundary catches up with it.
    static let provisionalFloor: CGFloat = 0.4
    /// **How fast a word's opacity eases toward its target** (batch 5, LC9):
    /// 90 % in 0.51 s. It shared `reflow` (0.26, 90 % at 0.60 s) until the
    /// plan's *"reaches its target within 0.6 s"* was measured at 0.60–0.66 s
    /// for a word appended at 0.4 s/word — the design point sat on the limit.
    /// How far an appended word counts for the centring (`appear`) keeps
    /// `reflow`: that is layout, and it moves with the rest of the line.
    static let fadeIn: CGFloat = 0.22
    /// **Words said are wiped after a pause** (Victor, 2026-09-26: *"cuvintele
    /// dictate trebuie să și dispară … un fade out ce vine din stânga când nu
    /// se mai transcrie nimic nou, până șterge tot textul; dacă reîncep să
    /// vorbesc, textul o ia din nou cu tot cu fade-ul surprins în acțiune"*).
    /// After `eraseAfter` seconds without a new word, an eraser front starts
    /// left of the screen and advances right at `eraseSpeed`, a soft edge
    /// `eraseEdge` wide; a new word freezes it where it stands on the line.
    /// **Five seconds, not two** (Victor, 2026-09-26 14:20: *"sus, în
    /// subtitrare, să nu dispară atât de repede textul; fade out-ul din stânga
    /// să înceapă la vreo cinci secunde"*): two seconds wiped a sentence while
    /// he was still reading it.
    /// **Letter by letter, not word by word** (same request: *"fade out-ul să
    /// se facă literă cu literă în cuvântul din stânga, nu cuvânt cu
    /// cuvânt"*): a word the soft edge crosses gets one opacity per glyph —
    /// see `drawWord(_:at:fill:alpha:glyphAlpha:)`.
    static let eraseAfter: CFTimeInterval = 5.0
    static let eraseSpeed: CGFloat = 260
    static let eraseEdge: CGFloat = 160

    private let panel: NSPanel
    private let view = TickerView()
    /// `CADisplayLink` from macOS 14; a 60 Hz timer below it.
    private var displayLink: Any?
    private var lastTick: CFTimeInterval = 0
    private(set) var isOpen = false

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: Self.bandHeight),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
    }

    // MARK: - Open / close

    /// Opens the band across the top of the screen under the pointer, empty,
    /// or fades it out. `RELAY_SHOOT` never shows it: it is not a chip state.
    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        if open {
            guard !RelayWindow.shooting else { isOpen = false; return }
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            guard let screen else { isOpen = false; return }
            let v = screen.visibleFrame
            panel.setFrame(NSRect(x: v.minX, y: v.maxY - Self.bandHeight, width: v.width, height: Self.bandHeight),
                           display: false)
            view.reset()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            startLink()
        } else {
            stopLink()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, !self.isOpen else { return }
                self.panel.orderOut(nil)
                self.view.reset()
            })
        }
    }

    /// For `GET /test/state`: `open`, and the ticker's numbers.
    func describe() -> [String: Any] {
        var out = view.describe()
        out["open"] = isOpen
        return out
    }

    /// The whole sentence as the recogniser has it now, revisions included.
    /// `gentle`: a batch correction of words behind him — softer tint, and it
    /// does not count as him speaking again (the eraser keeps sweeping).
    func setText(committed: String, partial: String, gentle: Bool = false) {
        guard isOpen else { return }
        let split: (String) -> [String] = { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
        let c = split(committed)
        view.setWords(c + split(partial), committed: c.count, gentle: gentle)
    }

    // MARK: - The clock

    private func startLink() {
        guard displayLink == nil else { return }
        lastTick = 0
        if #available(macOS 14, *) {
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick),
                              userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            displayLink = timer
        }
    }

    private func stopLink() {
        if #available(macOS 14, *), let link = displayLink as? CADisplayLink { link.invalidate() }
        (displayLink as? Timer)?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        defer { lastTick = now }
        guard lastTick > 0 else { return }
        // A frame after a stall (a hidden Space, a debugger) is clamped so the
        // line does not leap; it merely catches up at `accel`.
        let dt = CGFloat(min(now - lastTick, 1.0 / 20))
        view.advance(dt: dt, now: now, vMax: Self.vMax, ease: Self.ease,
                     marginRight: Self.marginRight, dropSlack: Self.dropSlack)
    }

    // MARK: - The view

    /// Draws one line of subtitle text at a fractional x and moves it.
    private final class TickerView: NSView {
        private var words: [String] = []
        /// Words at the head of `words` that have left through the left edge.
        private var dropped = 0
        /// Per visible word (`words[dropped + k]`): where it belongs in the
        /// new layout, and where it is drawn right now — the second eases
        /// toward the first (`reflow`), which is the elastic compression or
        /// extension of the rest of the line when a word behind is replaced.
        private var target: [CGFloat] = []
        private var shown: [CGFloat] = []
        private var widths: [CGFloat] = []
        /// x of the first drawn word (`words[dropped]`), in view points.
        private var anchor: CGFloat = 0
        private var velocity: CGFloat = 0
        /// **When a word replaced one already on screen**, by absolute index:
        /// invisible for the first half of `swap`, fading in over the second,
        /// then a faded yellow returning to white (*"corecțiile din spate să
        /// apară cu un galben șters și să facă fade înapoi la alb"*). Words
        /// merely appended, and the tail's punctuation flicker, are not
        /// corrections.
        private var bornAt: [Int: CFTimeInterval] = [:]
        /// The words a correction removed, fading out where they stood while
        /// the line reflows under them. `x` is relative to `anchor`.
        private var ghosts: [(word: String, x: CGFloat, since: CFTimeInterval)] = []
        private var now: CFTimeInterval = CACurrentMediaTime()
        private var correctionsShown = 0
        /// `words[..<committed]` are frozen by the server; the rest is provisional.
        private var committed = 0
        /// Per visible word: how solid it is drawn now, and where that is heading
        /// (1 once committed, `provisionalFloor`…1 across the open segment).
        private var opacity: [CGFloat] = []
        private var opacityTarget: [CGFloat] = []
        /// **How far each visible word has come in**, 0…1 — the share of its
        /// width the centring counts (2026-09-26, batch 5, LC2). An appended
        /// word starts at 0 and eases in with its own fade (τ `reflow`), so
        /// the line makes room for it exactly as fast as it becomes visible;
        /// every other word is 1. It counted whole from its first frame
        /// before, while still invisible, and the ease (τ 0.45) lagged every
        /// append: 109 pt off centre while narrow, 271 pt past the margin
        /// once wide, at 0.4 s/word.
        private var appear: [CGFloat] = []
        /// The centring goal of the previous frame, in view points; its
        /// motion is fed forward into the anchor (see `advance`). Nil until
        /// the first frame after a layout change.
        private var lastGoal: CGFloat?
        /// The eraser front in line coordinates (relative to `anchor`), once a
        /// pause has started it; `nil` while words keep coming.
        private var eraseFront: CGFloat?
        private var lastWordsAt: CFTimeInterval = CACurrentMediaTime()
        /// Per word drawn letter by letter in the last frame (the ones the
        /// eraser's soft edge crosses): each glyph's eraser opacity. For
        /// `GET /test/state` only.
        private var glyphAlphas: [[CGFloat]] = []

        override var isFlipped: Bool { false }
        override var wantsUpdateLayer: Bool { false }

        /// **Three passes, because one is muddy.** A single attributed string
        /// with fill + stroke + shadow draws the stroke pass *over* the fill,
        /// shadow included, and the white comes out grey (seen on the first
        /// screenshot, 2026-09-26). So: the shadow under everything, the black
        /// outline (a positive `strokeWidth` is stroke only, centred on the
        /// glyph edge), then the fill on top covering the inner half.
        private static let font = NSFont.systemFont(ofSize: LiveCaptionBand.fontSize, weight: .bold)
        private static let shadowAttributes: [NSAttributedString.Key: Any] = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            return [.font: font, .foregroundColor: NSColor.black, .shadow: shadow]
        }()
        private static let strokeAttributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.black, .strokeColor: NSColor.black, .strokeWidth: 9.0,
        ]
        private static let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white,
        ]
        /// The faded yellow a correction starts from — and the softer one a
        /// batch correction starts from (*"corecțiile intră blând, atenuat"*).
        private static let correctionColour = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.45, alpha: 1)
        private static let gentleColour = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.78, alpha: 1)
        /// Absolute indices of the words born gentle.
        private var gentleBorn = Set<Int>()
        private static let lineHeight = NSAttributedString(string: "Ag", attributes: fillAttributes).size().height

        /// The whole line's width in the layout the words are heading for.
        private var lineWidth: CGFloat { (target.last ?? 0) + (widths.last ?? 0) }
        /// …and as drawn this frame.
        private var shownWidth: CGFloat { (shown.last ?? 0) + (widths.last ?? 0) }
        /// The drawn end of the line with every appended word counted only as
        /// far as it has come in — the text the eye actually sees.
        private var visibleWidth: CGFloat {
            var end = shownWidth
            for k in appear.indices where k < widths.count { end -= (1 - appear[k]) * widths[k] }
            return end
        }

        /// What `GET /test/state` reports, for an assertion at a desk.
        func describe() -> [String: Any] {
            ["words": words.count, "dropped": dropped, "anchor": Double(anchor),
             "lineWidth": Double(lineWidth), "shownWidth": Double(shownWidth), "velocity": Double(velocity),
             "visibleWidth": Double(visibleWidth), "appear": appear.map { Double(($0 * 100).rounded() / 100) },
             "bandWidth": Double(bounds.width), "reflowing": Double(zip(shown, target).map { abs($0 - $1) }.max() ?? 0),
             "corrections": correctionsShown, "correcting": bornAt.keys.sorted(), "ghosts": ghosts.map { $0.word },
             "committed": committed, "opacity": opacity.map { Double(($0 * 100).rounded() / 100) },
             "eraseFront": eraseFront.map { Double($0) } ?? NSNull(),
             "eraseAfter": LiveCaptionBand.eraseAfter,
             "idleFor": Double(now - lastWordsAt),
             "glyphAlphas": glyphAlphas.map { $0.map { Double(($0 * 100).rounded() / 100) } }]
        }

        func reset() {
            words = []
            dropped = 0
            target = []; shown = []; widths = []
            anchor = 0
            velocity = 0
            bornAt = [:]
            gentleBorn = []
            ghosts = []
            correctionsShown = 0
            committed = 0
            opacity = []; opacityTarget = []
            appear = []; lastGoal = nil
            eraseFront = nil
            lastWordsAt = CACurrentMediaTime()
            glyphAlphas = []
            needsDisplay = true
        }

        func setWords(_ new: [String], committed newCommitted: Int, gentle: Bool = false) {
            guard new != words || newCommitted != committed else { return }
            committed = min(newCommitted, new.count)
            retarget()
            guard new != words else { return }
            let old = words
            let wasEmpty = old.isEmpty
            let stamp = CACurrentMediaTime()
            if !gentle { lastWordsAt = stamp }
            // **The eraser has wiped the whole line**: what comes next is a new
            // line entering from the right; the old words are dropped for real
            // (nothing visible moves — they were already gone).
            var freshLine = old.isEmpty
            if let front = eraseFront, front >= lineWidth, !old.isEmpty {
                dropped = old.count
                shown = []; opacity = []; appear = []
                bornAt = [:]; ghosts = []
                freshLine = true
            }
            // A revision that reaches back past what has already left: a new
            // line, placed in the centre like the first one was. **Nothing of
            // the old line is carried into it** (2026-09-26, batch 5, LC7): the
            // old words used to stay "visible" here — `dropped` had just been
            // zeroed — so they were aligned against the new ones, the new words
            // counted as three corrections, and the line glided in from the
            // left at 700 pt/s instead of appearing in the centre.
            if new.count <= dropped {
                dropped = 0; bornAt = [:]; ghosts = []; shown = []; opacity = []; appear = []; eraseFront = nil
                freshLine = true
            }
            // **Aligned, not compared by index**: a recogniser that turns
            // "cinci sute" into "500" shifts every later word one place, and
            // an index diff would paint the whole rest of the line yellow. The
            // longest common subsequence keeps every unchanged word's identity:
            // its own fade if it was a correction a moment ago, and the x it is
            // drawn at, which is what makes the reflow a glide and not a jump.
            let oldVisible = freshLine ? [] : Array(old.dropFirst(min(dropped, old.count)))
            let newVisible = Array(new.dropFirst(dropped))
            let pairs = Self.align(oldVisible, newVisible)
            var carried: [Int: CFTimeInterval] = [:]
            var carriedX: [Int: CGFloat] = [:]
            var carriedOpacity: [Int: CGFloat] = [:]
            var carriedAppear: [Int: CGFloat] = [:]
            var carriedGentle = Set<Int>()
            for (o, n) in pairs {
                if let at = bornAt[dropped + o] { carried[dropped + n] = at }
                if gentleBorn.contains(dropped + o) { carriedGentle.insert(dropped + n) }
                if o < shown.count { carriedX[n] = shown[o] }
                if o < opacity.count { carriedOpacity[n] = opacity[o] }
                if o < appear.count { carriedAppear[n] = appear[o] }
            }
            let matchedOld = Set(pairs.map { $0.0 })
            let matchedNew = Set(pairs.map { $0.1 })
            // Every old word no longer there fades out where it stood.
            for o in oldVisible.indices where !matchedOld.contains(o) && o < shown.count {
                ghosts.append((oldVisible[o], shown[o], stamp))
            }
            let lastMatchedNew = pairs.last?.1 ?? -1
            let lastMatchedOld = pairs.last?.0 ?? -1
            // Past the last aligned pair: words are corrections only if they
            // *replaced* something — old words were there and are now gone.
            let tailReplaced = lastMatchedOld < oldVisible.count - 1
            var appended = Set<Int>()
            for n in newVisible.indices where !matchedNew.contains(n) {
                guard n < lastMatchedNew || tailReplaced else { appended.insert(n); continue }
                carried[dropped + n] = stamp
                if gentle { carriedGentle.insert(dropped + n) }
                correctionsShown += 1
            }
            bornAt = carried
            gentleBorn = carriedGentle
            words = new
            // The new layout; each word starts where its old self was drawn,
            // or in place if it is new.
            widths = newVisible.map { Self.width(of: $0) }
            var x: CGFloat = 0
            target = widths.map { w in defer { x += w }; return x }
            shown = target.indices.map { carriedX[$0] ?? target[$0] }
            retarget()
            // A carried word keeps the opacity it had and eases from there; a
            // new one fades in from nothing (a correction has its own swap).
            opacity = target.indices.map { carriedOpacity[$0] ?? (carried[dropped + $0] == nil ? 0 : opacityTarget[$0]) }
            // An appended word comes in from 0; a correction takes its place in
            // the layout at once (the reflow glides the rest), so it counts whole.
            appear = target.indices.map { carriedAppear[$0] ?? (appended.contains($0) ? 0 : 1) }
            // A fresh line (first words, after a full wipe, or a revision past
            // the dropped words) is set in the centre at once, **at rest** — it
            // fades in there, it does not travel. The velocity is zeroed here
            // too: it was the previous frame's (the old line re-centring behind
            // the eraser), and a fresh line reported 109 pt/s on its first
            // frame while standing still (LC16).
            if oldVisible.isEmpty || wasEmpty || freshLine {
                eraseFront = nil
                appear = target.map { _ in 1 }
                anchor = centredAnchor()
                velocity = 0
            }
            // A jump of the goal made here (a correction, a fresh line) is eased
            // like it always was, not fed forward; only its motion from frame to
            // frame (a word coming in, the eraser) is. So the goal is re-read
            // here, in the new layout — nil would lose the first frame of every
            // append's motion to the slow ease, ~6 % of a word each time, which
            // added up to 20 pt past the margin at 0.4 s/word.
            lastGoal = centredAnchor()
            needsDisplay = true
        }

        /// Where the anchor belongs for the visible text to sit centred — or,
        /// when the visible text is wider than the band, for its end to sit
        /// inside the right margin.
        private func centredAnchor(marginRight: CGFloat = LiveCaptionBand.marginRight) -> CGFloat {
            guard !widths.isEmpty else { return anchor }
            var start = shown[0]
            if let front = eraseFront { start = max(start, front + LiveCaptionBand.eraseEdge / 2) }
            let end = visibleWidth
            let centred = bounds.width / 2 - (start + end) / 2
            return min(centred, bounds.width - marginRight - end)
        }

        /// Where each visible word's opacity is heading: solid once committed,
        /// then a ramp down to `provisionalFloor` at the newest word.
        private func retarget() {
            let visible = words.count - dropped
            let open = max(0, words.count - committed)
            opacityTarget = (0..<visible).map { k in
                let i = dropped + k
                guard i >= committed else { return 1 }
                let rank = CGFloat(i - committed + 1) / CGFloat(open)   // 1/open … 1
                return 1 - (1 - LiveCaptionBand.provisionalFloor) * rank
            }
            if opacity.count != opacityTarget.count {
                opacity = opacityTarget.indices.map { $0 < opacity.count ? opacity[$0] : opacityTarget[$0] }
            }
        }

        /// Longest common subsequence of two short word lists, as index pairs.
        /// **Words match on their stem, case-folded**: a commit that turns
        /// `world, how` into `world. How` has not changed a word, only the
        /// recogniser's punctuation and capitals — never a correction.
        static func align(_ a: [String], _ b: [String]) -> [(Int, Int)] {
            guard !a.isEmpty, !b.isEmpty else { return [] }
            let sa = a.map { stem($0).lowercased() }, sb = b.map { stem($0).lowercased() }
            var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    dp[i][j] = sa[i] == sb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
            var out: [(Int, Int)] = []
            var i = 0, j = 0
            while i < a.count, j < b.count {
                if sa[i] == sb[j] { out.append((i, j)); i += 1; j += 1 }
                else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 } else { j += 1 }
            }
            return out
        }

        private static func stem(_ word: String) -> Substring {
            var s = Substring(word)
            while let last = s.last, last.isPunctuation { s = s.dropLast() }
            return s
        }

        /// A word's advance, trailing space included.
        private static func width(of word: String) -> CGFloat {
            NSAttributedString(string: word + " ", attributes: fillAttributes).size().width
        }

        func advance(dt: CGFloat, now: CFTimeInterval, vMax: CGFloat,
                     ease: CGFloat, marginRight: CGFloat, dropSlack: CGFloat) {
            self.now = now
            guard !words.isEmpty, !widths.isEmpty else { return }
            // The reflow: every word eases toward its place in the new layout,
            // toward how solid it should be, and an appended word toward being
            // counted whole — all before the anchor moves, so the goal below is
            // this frame's.
            let k = 1 - exp(-dt / LiveCaptionBand.reflow)
            for i in shown.indices {
                let d = target[i] - shown[i]
                shown[i] += abs(d) < 0.3 ? d : d * k
            }
            let kf = 1 - exp(-dt / LiveCaptionBand.fadeIn)
            for i in opacity.indices where i < opacityTarget.count {
                let d = opacityTarget[i] - opacity[i]
                opacity[i] += abs(d) < 0.005 ? d : d * kf
            }
            // A long word comes in a little slower, so the room it needs is
            // made under `vMax` (its peak rate is width / τ, kept to 0.7 of it so the
            // tail of the previous word still coming in fits too): a 200 pt word at
            // τ 0.26 would ask 770 pt/s, be capped, and stand 4 pt past the
            // margin for a frame or two.
            for i in appear.indices {
                let d = 1 - appear[i]
                let tau = i < widths.count ? max(LiveCaptionBand.reflow, widths[i] / (0.7 * vMax)) : LiveCaptionBand.reflow
                appear[i] += d < 0.005 ? d : d * (1 - exp(-dt / tau))
            }
            // **The anchor tracks the centred position** (batch 5, LC2): the
            // goal's own motion since the last frame — a word coming in, the
            // eraser's front — is fed forward, so a steady stream of words is
            // followed without lag; what is left of the gap (a correction's
            // jump) eases as before, the same fraction per `ease` seconds.
            // Never faster than `vMax` either way.
            let goal = centredAnchor(marginRight: marginRight)
            let fed = lastGoal.map { goal - $0 } ?? 0
            lastGoal = goal
            var step = fed + (goal - anchor - fed) * (1 - exp(-dt / ease))
            step = max(-vMax * dt, min(vMax * dt, step))
            if abs(goal - anchor) < 0.3 { step = goal - anchor }
            velocity = abs(step) / max(dt, 0.0001)
            anchor += step
            // **The eraser**: nothing new for `eraseAfter` → a front starts left
            // of the screen and sweeps right; a new word froze it (it no longer
            // advances) and it rides the line from then on.
            if now - lastWordsAt >= LiveCaptionBand.eraseAfter {
                let front = eraseFront ?? (-anchor - LiveCaptionBand.eraseEdge)
                eraseFront = min(lineWidth, front + LiveCaptionBand.eraseSpeed * dt)
            }
            // Drop what has fully gone, advancing the anchor by its own width so
            // every remaining glyph stays exactly where it was drawn.
            while widths.count > 1 {
                let w = widths[0]
                let gone = anchor + w < -dropSlack || (eraseFront.map { shown[0] + w < $0 } ?? false)
                guard gone, abs(shown[1] - target[1]) < 0.5 else { break }
                anchor += w
                bornAt[dropped] = nil
                dropped += 1
                widths.removeFirst(); target.removeFirst(); shown.removeFirst()
                if !opacity.isEmpty { opacity.removeFirst() }
                if !opacityTarget.isEmpty { opacityTarget.removeFirst() }
                if !appear.isEmpty { appear.removeFirst() }
                // The goal moves by the same width the anchor just did.
                if let g = lastGoal { lastGoal = g + w }
                for i in target.indices { target[i] -= w; shown[i] -= w }
                for i in ghosts.indices { ghosts[i].x -= w }
                if let front = eraseFront { eraseFront = front - w }
            }
            let fadeOut = LiveCaptionBand.swap / 2
            ghosts.removeAll { now - $0.since >= fadeOut }
            for (i, at) in bornAt where now - at > LiveCaptionBand.swap + LiveCaptionBand.correctionFade { bornAt[i] = nil }
            needsDisplay = true
        }

        /// The fill colour and the opacity of visible word `k`: its swap fade-in
        /// if it is a correction, times how solid it is. The eraser is not in
        /// it: `draw` applies that per word or per glyph (`erasure(_:)`).
        private func look(_ k: Int) -> (NSColor, CGFloat) {
            var alpha = k < opacity.count ? opacity[k] : 1
            var colour = NSColor.white
            if let at = bornAt[dropped + k] {
                let t = now - at
                let half = LiveCaptionBand.swap / 2
                alpha *= CGFloat(min(1, max(0, (t - half) / half)))
                let warm = CGFloat(min(1, max(0, (t - LiveCaptionBand.swap) / LiveCaptionBand.correctionFade)))
                let start = gentleBorn.contains(dropped + k) ? Self.gentleColour : Self.correctionColour
                colour = start.blended(withFraction: warm, of: .white) ?? .white
            }
            return (colour, alpha)
        }

        /// 0 behind the eraser front, 1 past its soft edge.
        private func erased(at x: CGFloat) -> CGFloat {
            guard let front = eraseFront else { return 1 }
            return min(1, max(0, (x - front) / LiveCaptionBand.eraseEdge))
        }

        /// How the eraser treats visible word `k`: `whole(a)` — one opacity
        /// for the word (1 past the soft edge, 0 behind the front, or no eraser
        /// running); `glyphs` — the soft edge crosses the word's span, so each
        /// letter gets its own.
        private enum Erasure { case whole(CGFloat), glyphs }
        private func erasure(_ k: Int) -> Erasure {
            guard let front = eraseFront else { return .whole(1) }
            let start = shown[k], end = shown[k] + widths[k]
            if start >= front + LiveCaptionBand.eraseEdge { return .whole(1) }
            if end <= front { return .whole(0) }
            return .glyphs
        }

        /// Each letter's x inside `word` (from its left edge), and one past the
        /// last: the typesetter's own caret offsets, so a word drawn whole and
        /// the same word's letters land on the same pixels, kerning included.
        private static func glyphEdges(of word: String) -> [CGFloat] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: word, attributes: fillAttributes))
            let ns = word as NSString
            var edges: [CGFloat] = []
            var i = word.startIndex
            while i < word.endIndex {
                let u = i.utf16Offset(in: word)
                edges.append(CTLineGetOffsetForStringIndex(line, u, nil))
                i = word.index(after: i)
            }
            edges.append(CTLineGetOffsetForStringIndex(line, ns.length, nil))
            return edges
        }

        /// A word drawn as one translucent group: the three passes inside a
        /// transparency layer at `alpha`. With `glyphAlpha`, **the eraser
        /// fades it letter by letter** (2026-09-26 14:20): once the three
        /// passes are in the layer, each letter's column is multiplied by its
        /// own opacity (`destinationIn`), so letter *n* is dimmer than *n+1*.
        /// One layer for the word rather than one per letter, because a
        /// letter's black outline reaches ~4.5 pt past its edge and, drawn
        /// after its left neighbour, would bite into that neighbour's white —
        /// the muddy fill the three passes exist to avoid.
        private func drawWord(_ word: String, at: NSPoint, fill: NSColor, alpha: CGFloat,
                              glyphAlpha: ((CGFloat) -> CGFloat)? = nil) {
            guard alpha > 0.01, let ctx = NSGraphicsContext.current?.cgContext else { return }
            var columns: [(x0: CGFloat, x1: CGFloat, a: CGFloat)] = []
            if let glyphAlpha {
                let edges = Self.glyphEdges(of: word)
                guard edges.count > 1 else { return }
                // The first and last columns reach out to cover the shadow and
                // outline beyond the letters; anything the columns miss would
                // stay at full opacity.
                let reach: CGFloat = 40
                var alphas: [CGFloat] = []
                for j in 0..<(edges.count - 1) {
                    let a = glyphAlpha((edges[j] + edges[j + 1]) / 2)
                    alphas.append(a)
                    let x0 = j == 0 ? edges[j] - reach : edges[j]
                    let x1 = j == edges.count - 2 ? edges[j + 1] + reach : edges[j + 1]
                    columns.append((at.x + x0, at.x + x1, a))
                }
                glyphAlphas.append(alphas)
                guard alphas.contains(where: { $0 * alpha > 0.01 }) else { return }
            }
            let faded = alpha < 0.999 || !columns.isEmpty
            if faded { ctx.saveGState(); ctx.setAlpha(alpha); ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
            NSAttributedString(string: word, attributes: Self.shadowAttributes).draw(at: at)
            NSAttributedString(string: word, attributes: Self.strokeAttributes).draw(at: at)
            var attrs = Self.fillAttributes
            attrs[.foregroundColor] = fill
            NSAttributedString(string: word, attributes: attrs).draw(at: at)
            if !columns.isEmpty {
                ctx.saveGState()
                ctx.setBlendMode(.destinationIn)
                for c in columns {
                    ctx.setFillColor(NSColor.black.withAlphaComponent(c.a).cgColor)
                    ctx.fill(CGRect(x: c.x0, y: bounds.minY, width: c.x1 - c.x0, height: bounds.height))
                }
                ctx.restoreGState()
            }
            if faded { ctx.endTransparencyLayer(); ctx.restoreGState() }
        }

        override func draw(_ dirtyRect: NSRect) {
            guard !words.isEmpty, !widths.isEmpty else { return }
            let y = ((bounds.height - Self.lineHeight) / 2).rounded()
            let visible = Array(words[dropped...])
            // The settled words first, in three passes over the whole line so
            // a word's fill never sits under its neighbour's shadow; then the
            // ghosts and the words fading in, each as its own translucent group.
            // A word the eraser's soft edge crosses is drawn letter by letter
            // (at most two per frame: the edge is 160 pt, a word ~100–250);
            // one wholly behind the front is not drawn at all.
            var fading: [(String, NSPoint, NSColor, CGFloat)] = []
            var lettered: [(String, NSPoint, NSColor, CGFloat, CGFloat)] = []
            glyphAlphas = []
            for pass in 0..<3 {
                for (k, word) in visible.enumerated() where k < shown.count {
                    let at = NSPoint(x: anchor + shown[k], y: y)
                    var (fill, alpha) = look(k)
                    switch erasure(k) {
                    case .whole(let a): alpha *= a
                    case .glyphs:
                        if pass == 0 { lettered.append((word, at, fill, alpha, shown[k])) }
                        continue
                    }
                    if alpha < 0.999 { if pass == 0 { fading.append((word, at, fill, alpha)) }; continue }
                    switch pass {
                    case 0: NSAttributedString(string: word, attributes: Self.shadowAttributes).draw(at: at)
                    case 1: NSAttributedString(string: word, attributes: Self.strokeAttributes).draw(at: at)
                    default:
                        var attrs = Self.fillAttributes
                        attrs[.foregroundColor] = fill
                        NSAttributedString(string: word, attributes: attrs).draw(at: at)
                    }
                }
            }
            let fadeOut = LiveCaptionBand.swap / 2
            for g in ghosts {
                let alpha = CGFloat(1 - min(1, (now - g.since) / fadeOut)) * erased(at: g.x)
                drawWord(g.word, at: NSPoint(x: anchor + g.x, y: y), fill: .white, alpha: alpha)
            }
            for (word, at, fill, alpha) in fading { drawWord(word, at: at, fill: fill, alpha: alpha) }
            for (word, at, fill, alpha, lineX) in lettered {
                drawWord(word, at: at, fill: fill, alpha: alpha) { [unowned self] x in self.erased(at: lineX + x) }
            }
        }
    }
}
