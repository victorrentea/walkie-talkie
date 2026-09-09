import AppKit
import QuartzCore

/// **A golden halo round the pointer whenever a dictation is headed for the
/// caret — faint while he talks, and swelling once he stops.**
///
/// Victor's ask, 2026-09-09: *"when this mode is activated … draw a little halo
/// ring around the mouse … about 100 pixels, to warn me that I need to basically
/// pick somewhere to paste it"*.
///
/// ## What it is warning about
///
/// Every other destination this app has is a thing he **pointed at** and a thing
/// the chip **names**: a terminal's icon and `petclinic@main`, a picked folder,
/// `✨` for a session that does not exist yet. A caret dictation names its
/// destination too — `at caret` — and that is exactly the problem: it is the one
/// destination that is not a place, it is *wherever the focus happens to be when
/// the words arrive*. A sentence spoken with the focus in the wrong window is
/// pasted into the wrong window, discovered afterwards, with nothing having said
/// so at the time.
///
/// **Whether or not a terminal is bound**, and it shipped the other way for an
/// hour. The gate was `pasteMode && !isBound`, on the reading that a binding is
/// a second answer to *where do these words go*. It is not — in this mode they
/// go to the caret either way, so the failure is exactly as available bound as
/// unbound. Victor: *"nu ne-legat e cheia, ci dacă transcriu at caret (legat sau
/// nu)"*. If anything bound is the worse case: the chip carries a terminal's
/// name and icon all day, so `at caret` is the row that has to be *noticed*
/// changing.
///
/// The chip cannot carry this. It rides beside the pointer, and macOS hides the
/// pointer the moment he touches the keyboard — which is precisely the gesture
/// this is about. So the warning is drawn round the pointer instead of beside
/// it: a ring is visible at the edge of vision without being read, and what it
/// is drawn round is the thing he has to move.
///
/// ## The swell is the whole message, and silence is what triggers it
///
/// *"this halo should increase in opacity the moment there is no voice coming
/// any more … by default it's 10% … but grows up to 50% after two seconds of low
/// voice … over another two seconds"*.
///
/// While he is talking the paste is not imminent and the ring has nothing to
/// ask, so it sits at `rest` — present, ignorable, and there to be recognised
/// later rather than read now. **Stopping is the signal**: the sentence he has
/// just finished is about to be pasted, and it is the last moment placing the
/// caret is still free. So the ring is quiet exactly while he is busy and
/// insistent exactly when he is not, which is the opposite of what a fixed
/// warning does.
///
/// **Two seconds before it starts, not immediately**, because the gaps *inside*
/// a sentence are ordinary: he pauses to think mid-dictation all the time, and a
/// ring that brightened on every breath would be a light flashing at the corner
/// of his eye for the length of every sentence — the same failure that keeps the
/// `HQ` tag's pop edge-triggered. Two seconds of nothing is a stop.
///
/// ## What it does not do
///
/// It does not move the caret, name a window, or refuse anything. It is drawn on
/// `ignoresMouseEvents`, so a click through it lands where it would have landed,
/// and there is nothing to press: the correction is to click where the words
/// should go, which is a gesture he already makes.
///
/// **Never in a screenshot** (`sharingType = .none`) — the shutter is live in
/// Replace Wispr, so this would otherwise be a blue ring burned into the very
/// frames it is standing over. Same rule the beacon, the capture flash and the
/// menu-bar mirror follow, and the same consequence: it cannot be reviewed with
/// a screenshot, only through `CGWindowListCopyWindowInfo` and his own eyes.
final class CaretHalo {

    /// **The core of the halo sits at 150pt out**, three times the radius the
    /// ring shipped at a few hours earlier.
    ///
    /// 100pt across was picked as the smallest circle that still reads as one
    /// round a 20pt cursor, which answered the wrong question: this is not a
    /// mark *on* the pointer, it is the only thing on screen saying where a
    /// whole sentence is about to land. At that size and 10% it was polite to
    /// the point of being missable — exactly the failure it exists to prevent.
    /// This is a presence in the periphery rather than an ornament to be looked
    /// at, which is the one place it has to work: he is reading something else
    /// while he talks.
    private static let core: CGFloat = 150
    /// How far the glow reaches past the core, as a multiple of it. The tail is
    /// what makes it a halo rather than a hoop — see `profile`.
    private static let reach: CGFloat = 1.45
    /// The panel has to hold the whole tail: a gradient clipped by its own
    /// window ends in a hard circular edge, which is the one thing this shape
    /// must not have.
    private static var side: CGFloat { (core * reach).rounded() * 2 + 4 }

    /// **The halo's cross-section**, as `(distance from the pointer ÷ core,
    /// colour)` — read straight off the reference picture Victor sent
    /// (2026-09-09, *"ca un halou"*).
    ///
    /// Three things in that picture are what make it read as light rather than
    /// as a drawn band, and all three are in this table:
    ///
    /// - **The bright edge is the inner one**, very nearly white and warm, with
    ///   the deeper gold sitting outside it. That is how a glow round a hole
    ///   behaves and it is the opposite of a stroked ring, which is brightest in
    ///   the middle of its own width.
    /// - **The outer falloff is long and the inner one short.** The hole stays
    ///   clean — which matters here for a reason the picture does not know
    ///   about: what is inside it is the pointer and whatever he is aiming it
    ///   at.
    /// - **Nothing has an edge.** Every stop either starts or ends at zero
    ///   alpha, so there is no radius at which the alpha steps.
    ///
    /// **It is drawn rather than shipped as that PNG**, which was the literal
    /// reading of *"uite o imagine de folosit"*. The picture has an opaque light
    /// grey background baked into it, so over a dark editor — where this spends
    /// half its life — it would be a grey square with a halo in it. A gradient
    /// has real transparency, costs no asset, is resolution-free, and takes the
    /// panel's own opacity when the swell brightens it.
    private static let profile: [(CGFloat, NSColor)] = [
        (0.00, glow(1.00, 0.97, 0.86, 0)),
        (0.78, glow(1.00, 0.97, 0.86, 0)),
        (0.88, glow(1.00, 0.92, 0.68, 0.55)),
        (0.95, glow(1.00, 0.90, 0.62, 0.95)),   // the bright inner rim
        (1.05, glow(1.00, 0.78, 0.28, 0.90)),   // gold, the body
        (1.18, glow(0.98, 0.65, 0.15, 0.45)),
        (1.32, glow(0.96, 0.60, 0.12, 0.15)),
        (1.45, glow(0.96, 0.60, 0.12, 0)),
    ]

    private static func glow(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// What it looks like while he is talking: there, and no more than that.
    private static let rest: CGFloat = 0.10
    /// And once he has stopped. Half-opaque is loud for something riding the
    /// pointer, which is the point — by then it is the only thing on screen
    /// asking the question.
    private static let alert: CGFloat = 0.50
    /// How long a silence has to last before the ring reads it as a stop rather
    /// than as him thinking mid-sentence.
    private static let patience: TimeInterval = 2
    /// And how long it then takes to get there.
    private static let swell: TimeInterval = 2

    /// 20 Hz, the beacon's rate and for the beacon's reason: the value is a
    /// continuous function of how long he has been quiet, so it is *sampled*
    /// rather than animated — an animation would be interpolating toward a
    /// target that has already moved.
    private static let tick: TimeInterval = 1.0 / 20

    private var panel: RelayPanel?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var live = false

    /// **How long since he last said anything**, asked of whoever is holding the
    /// microphone. A closure for the reason `RecordingBeacon.level` is one: what
    /// is listening is the delegate's business, not this class's.
    var quietSeconds: (() -> TimeInterval)?

    /// On or off. Idempotent, and driven from `syncBorrowedGestures` — the one
    /// switch every edge of a dictation already passes through, so this cannot
    /// drift out of step with the chip, the beacon or the borrowed buttons.
    func setActive(_ on: Bool) {
        guard live != on else { return }
        live = on
        // Both edges, for the reason the selection watcher logs both: "why did
        // the ring not come up" has to be answerable from the file, and the
        // three conditions behind it are not all visible on screen.
        Log.info(on ? "◯ caret halo on — these words go wherever the caret is"
                    : "◯ caret halo off")
        on ? show() : hide()
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        panel.alphaValue = Self.rest
        follow()
        panel.orderFrontRegardless()

        // Global catches every other app the pointer moves over; local catches
        // this app's own panels, which never see a global monitor's events —
        // the chip is riding the same cursor and is not click-through, so
        // without the local half the ring would stop dead whenever the pointer
        // crossed it.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                             .rightMouseDragged, .otherMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.follow()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in
            self?.follow(); return e
        }) { monitors.append(m) }

        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.refresh() }
        timer = t
        // `.common`, because the chords that reach this app are held mouse
        // buttons and a tracking loop would otherwise stall the swell.
        RunLoop.main.add(t, forMode: .common)
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        panel?.orderOut(nil)
    }

    /// Centred on the pointer, every time the pointer reports. Off the events
    /// rather than off a timer for `RelayWindow.startFollowingMouse`'s measured
    /// reason: a 60 Hz poll trails a fast pointer by a whole tick plus a
    /// window-move round trip, and a ring that lags is a ring that is visibly
    /// not *round* anything.
    private func follow() {
        guard live, let panel = panel else { return }
        let p = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: (p.x - Self.side / 2).rounded(),
                                     y: (p.y - Self.side / 2).rounded()))
    }

    private func refresh() {
        guard live, let panel = panel else { return }
        let quiet = quietSeconds?() ?? 0
        let t = max(0, min(1, (quiet - Self.patience) / Self.swell))
        panel.alphaValue = Self.rest + (Self.alert - Self.rest) * CGFloat(t)
    }

    /// **A radial gradient, not a stroked path**, because the whole shape is a
    /// falloff: a `CAShapeLayer`'s stroke has one alpha across its width and
    /// would give the hard hoop the picture is emphatically not.
    ///
    /// For `.radial` the start point is the centre and the end point sets the
    /// extent, so with (0.5, 0.5) → (1, 1) a stop at `t` sits at radius
    /// `t × side / 2`. That is the whole of the arithmetic: `profile` is in
    /// multiples of the core radius, and this turns it into fractions of the
    /// panel's half-width.
    ///
    /// Built here rather than inline in `makePanel` so `shoot` draws the same
    /// layer the panel does — a contact sheet of a *different* gradient would be
    /// worse than none.
    static func haloLayer(side: CGFloat) -> CAGradientLayer {
        let ring = CAGradientLayer()
        ring.type = .radial
        ring.frame = CGRect(x: 0, y: 0, width: side, height: side)
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 1, y: 1)
        let half = side / 2
        ring.colors = profile.map { $0.1.cgColor }
        ring.locations = profile.map { NSNumber(value: Double(min(1, $0.0 * core / half))) }
        return ring
    }

    private func makePanel() -> RelayPanel {
        let side = Self.side
        // `RelayPanel`, not `NSPanel`: AppKit's `constrainFrameRect` drags a
        // borderless window back onto the display and below the menu bar, which
        // for something pinned to the pointer is precisely wrong — at the top of
        // the screen it would shove the ring off the cursor to keep it whole.
        let p = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = .none

        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer?.addSublayer(Self.haloLayer(side: side))
        p.contentView = view

        panel = p
        return p
    }
}

// MARK: - Looking at it

/// **Draw the halo onto a dark ground and a light one, and quit** —
/// `WT_SHOOT_HALO=/tmp/halo.png`.
///
/// The panel is `sharingType = .none` like everything else this app puts near
/// the pointer, so **no screen capture can contain it**: the only way to judge a
/// falloff was to start a caret dictation and look, which answers *is it there*
/// and not *does it look like the picture he sent*. Same problem
/// `docs/overlay-states.html`, `WT_SHOOT_MENU` and `WT_SHOOT_WIPE` were built
/// for, same answer — the real layer drawing itself.
///
/// **Two grounds, because this shape spends its life over both** and a halo that
/// reads on one can vanish on the other; that is precisely the fault that took
/// the ring off blue. Each is drawn twice, at the resting opacity and at the
/// alarmed one, which are the two states there are.
extension CaretHalo {
    static func shoot(to path: String) {
        let side = Self.side
        let cell = NSSize(width: side, height: side)
        let grounds: [NSColor] = [NSColor(white: 0.11, alpha: 1), NSColor(white: 0.97, alpha: 1)]
        let alphas: [CGFloat] = [rest, alert]
        let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(alphas.count),
                                         height: cell.height * CGFloat(grounds.count)))
        sheet.lockFocus()
        for (row, ground) in grounds.enumerated() {
            for (col, alpha) in alphas.enumerated() {
                let box = NSRect(x: cell.width * CGFloat(col), y: cell.height * CGFloat(row),
                                 width: cell.width, height: cell.height)
                ground.setFill()
                box.fill()
                let host = NSView(frame: NSRect(origin: .zero, size: cell))
                host.wantsLayer = true
                host.layer?.addSublayer(haloLayer(side: side))
                // **The opacity is applied once, in the draw.** Setting it on
                // the host *as well* squared it — the resting column came out at
                // 1% and looked like a bug in the gradient rather than in the
                // sheet, which is the exact way a contact sheet can lie.
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    NSImage(size: cell, flipped: false) { r in rep.draw(in: r) }
                        .draw(in: box, from: .zero, operation: .sourceOver, fraction: alpha)
                }
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
