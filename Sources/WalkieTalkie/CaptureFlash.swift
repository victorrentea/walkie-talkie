import AppKit
import QuartzCore

/// The shutter's receipt: the frame he just took flies into the chip's `📸`,
/// and a mark blooms where the pointer was.
///
/// **The picture goes into the counter, not a border round the screen**
/// (2026-09-23). It was a yellow vignette — gradient edges fading inward over
/// the whole display, Victor Addons' capture flash — and it answered *did that
/// press land* by lighting up everything except the thing that changed. Victor:
/// *"there's an effect that takes that photo … and zooms it … into the icon that
/// shows the number of photos. That can avoid you having to draw a yellow border
/// around the screen … The feeling is much better if you just bring it into the
/// tooltip."* The frame shrinks from where it was taken — the display, or the
/// area he dragged — onto the `📸 ×N` it has just incremented, so the receipt
/// and the total are one motion instead of two places to look.
///
/// Click-through and above everything, so it never interrupts what he is doing.
enum CaptureFlash {
    private static var activePanels: [NSPanel] = []

    /// How long a frame takes to shrink into the chip. Short, because it plays
    /// over his work on every shot; long enough to be *followed* to the chip,
    /// which is the whole of what it says.
    static let intoChipDuration: CFTimeInterval = 0.5

    /// The white edge the flying frame wears, at its start — Victor's *"several-
    /// pixel border"*. A full-screen picture lying exactly on the screen it was
    /// taken of is invisible; the edge is what makes it a *thing* that then
    /// leaves. It thins as the picture shrinks, or a 4 pt frame round a 16 pt
    /// thumbnail is all frame.
    private static let intoChipBorder: CGFloat = 4

    /// **Fly `picture` from `source` into `target`**, both in global Cocoa
    /// coordinates. `source` is where the pixels were on screen (the display,
    /// or the dragged area), so the flight starts pixel for pixel on top of what
    /// it is a picture of; `target` is the chip's `📸` (`RelayWindow.shotLanding`).
    ///
    /// It arrives at the glyph's size with the picture's own aspect, under the
    /// chip (one level below `.statusBar`, like `BindFlight`), so the last thing
    /// it does is slide beneath the counter rather than cover it.
    ///
    /// One panel on the screen the picture came from: the chip rides the pointer,
    /// and the pointer is on that screen for every shutter path.
    /// `sharingType = .none`, so a second press a moment later cannot photograph
    /// the first one's picture in flight.
    static func flyIntoChip(_ picture: CGImage, from source: CGRect, to target: CGRect) {
        guard source.width > 1, source.height > 1 else { return }
        let middle = NSPoint(x: source.midX, y: source.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(middle, $0.frame, false) })
                ?? NSScreen.main else { return }

        let panel = RelayPanel(contentRect: screen.frame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let local = { (r: CGRect) in r.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }

        // The picture's own aspect at the glyph's size: a frame squeezed square
        // on the way in would stop reading as the frame he took.
        let aspect = source.width / source.height
        let side = max(12, min(max(target.width, target.height), 28))
        let landing = aspect >= 1
            ? CGSize(width: side, height: side / aspect)
            : CGSize(width: side * aspect, height: side)
        let from = local(source)
        let to = CGRect(x: target.midX - landing.width / 2, y: target.midY - landing.height / 2,
                        width: landing.width, height: landing.height).offsetBy(
                            dx: -screen.frame.minX, dy: -screen.frame.minY)

        let frame = CALayer()
        frame.contents = picture
        frame.contentsGravity = .resize
        frame.masksToBounds = true
        frame.borderColor = NSColor.white.cgColor
        frame.cornerRadius = 8
        frame.borderWidth = intoChipBorder
        frame.frame = from
        view.layer?.addSublayer(frame)

        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        activePanels.append(panel)

        // Model values first, at the end state, with no implicit animation; the
        // explicit ones below carry it there.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.bounds = CGRect(origin: .zero, size: to.size)
        frame.position = CGPoint(x: to.midX, y: to.midY)
        frame.borderWidth = 1
        frame.cornerRadius = 2
        frame.opacity = 0
        CATransaction.commit()

        // Slow off the screen, fast into the chip: it leaves unhurriedly enough
        // to be seen leaving, and is *drawn in* at the end — the counter taking
        // it, rather than the picture arriving and stopping.
        let curve = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.8, 0.6)
        func animate(_ key: String, _ a: Any, _ b: Any) {
            let anim = CABasicAnimation(keyPath: key)
            anim.fromValue = a
            anim.toValue = b
            anim.duration = intoChipDuration
            anim.timingFunction = curve
            frame.add(anim, forKey: key)
        }
        animate("bounds", NSValue(rect: CGRect(origin: .zero, size: from.size)),
                NSValue(rect: CGRect(origin: .zero, size: to.size)))
        animate("position", NSValue(point: CGPoint(x: from.midX, y: from.midY)),
                NSValue(point: CGPoint(x: to.midX, y: to.midY)))
        animate("borderWidth", intoChipBorder, 1)
        animate("cornerRadius", 8, 2)
        // Whole until it is at the glyph, then gone into it.
        let life = CAKeyframeAnimation(keyPath: "opacity")
        life.values = [1, 1, 0]
        life.keyTimes = [0, 0.8, 1]
        life.duration = intoChipDuration
        frame.add(life, forKey: "life")

        DispatchQueue.main.asyncAfter(deadline: .now() + intoChipDuration) {
            panel.orderOut(nil)
            activePanels.removeAll { $0 === panel }
        }
    }

    /// A frame on disk as a `CGImage`, for `flyIntoChip`. Off the main thread —
    /// it decodes a JPEG.
    static func loadPicture(_ path: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Drop a target on the spot the pointer was standing when the shutter went.
    /// The picture itself goes into the chip once it exists (`flyIntoChip`);
    /// this is the half that can land at the press.
    ///
    /// **The reticle says where he was pointing while he said it.** Every shot the relay takes already carries
    /// that reading twice — burned into the picture for Victor, and in the file
    /// name for the agent — and both of those are things you find *afterwards*.
    /// This is the same fact at the only moment it can still be corrected: if
    /// the target lands somewhere he did not mean, the sentence is still being
    /// spoken and he can point again with the back button.
    ///
    /// It is the mark Victor Addons drops after every ⌃P, and deliberately so —
    /// that desktop already means "here" by it, so there is nothing to learn.
    ///
    /// `cursor` is where the gesture happened, passed in for the same reason
    /// `ScreenCapture.grab` takes it: this runs a clipboard probe and a
    /// subprocess ahead of the capture, and by the time anything reads
    /// `NSEvent.mouseLocation` again the hand has moved on.
    ///
    /// `cycleMarker` (2026-09-04, Victor's ask): a live A/B/C playtest of the
    /// two `CaptureEffects` prototypes he'd been tuning that session (spikes,
    /// tap ripple) against the classic red reticle — every real capture marker
    /// round-robined through all three so he could compare them in actual daily
    /// use, not just the demo harness. Both callers opt in — the
    /// dictation-start call (`captureContext`) and the mid-dictation "one more
    /// shot" call (`plusOneShot`) — sharing one rotation index, so the sequence
    /// kept advancing across both kinds of capture rather than each restarting
    /// its own cycle.
    ///
    /// **Decided 2026-09-06: the tap ripple, on its own.** See
    /// `markerRotation` — the losers are commented out in the list, not
    /// removed, and this flag still means "the chosen effect rather than the
    /// classic reticle".
    ///
    /// Synchronous when already on the main thread. Callers use this *before*
    /// their slow work (AX probe, screencapture) precisely so the panel is on
    /// screen first; an unconditional async hop would queue the flash behind that
    /// work and reintroduce the lag it exists to remove.
    static func announce(cursor: NSPoint? = nil, cycleMarker: Bool = false) {
        let point = cursor ?? NSEvent.mouseLocation
        let show = {
            if cycleMarker, let effect = nextMarkerEffect() {
                effect.play(at: point)
            } else {
                markCursor(at: point)
            }
        }
        if Thread.isMainThread { show() } else { DispatchQueue.main.async(execute: show) }
    }

    /// The round-robin state for `cycleMarker`: `nil` means "the classic red
    /// reticle" (`markCursor`), so the cycle *was* current → spikes → tap
    /// ripple → current → ... Only ever touched on the main thread (both call
    /// sites go through `announce`'s main-thread `show` closure), so no lock
    /// needed.
    ///
    /// **The playtest is over and the tap ripple won** (Victor, 2026-09-06):
    /// the other two are commented out rather than deleted, so the list is
    /// still the whole ballot and putting one back is uncommenting it. With a
    /// single entry the rotation is a constant — every capture marker is now
    /// the ripple — and the machinery around it costs nothing, so it stays
    /// where the next comparison can use it.
    private static var markerRotationIndex = 0
    private static let markerRotation: [CaptureEffect?] = [
        // nil,        // the classic red reticle (`markCursor`)
        // .spikes,    // concentric spikes
        .tapRipple,
    ]

    private static func nextMarkerEffect() -> CaptureEffect? {
        let effect = markerRotation[markerRotationIndex % markerRotation.count]
        markerRotationIndex += 1
        return effect
    }

    /// The red target, on screen, at `point` in global Cocoa coordinates.
    ///
    /// The animation is Victor Addons' `ScreenCaptureFlash.markCursor`, values
    /// included: it lands at **1.3× and settles to 0.9× over 0.35s**, so it reads
    /// as a scope being brought down onto the spot rather than a badge appearing
    /// beside one, and what stays behind is the smaller, quieter mark. It is at
    /// **80% from the first frame** with the only fade in its last quarter — a
    /// mark that fades *in* asks to be watched arriving, and this one has to be
    /// already there when the eye gets to it.
    ///
    /// The 0.35s zoom is untouched by the shorter life: it is the gesture of a
    /// scope coming down on the spot, and stretching or clipping it to fit a
    /// duration would cost the one part that is read as movement.
    ///
    /// `sharingType = .none`, like the vignette: the relay photographs the
    /// screen milliseconds after this appears, and the confirmation of a capture
    /// must never be inside the capture it confirms.
    /// **It arrives small and leaves large.** It used to land at 1.3× and settle
    /// to 0.9× over 0.35s — a scope being brought down onto a spot — and then sit
    /// there for the rest of 1.2 seconds. Sitting is the part that was wrong: the
    /// mark is over the very line or button he is describing, and a shape that
    /// holds still on top of it for a second is something to wait out. Blooming
    /// outward instead means the pixels it covered are uncovered by the same
    /// motion that makes it noticeable, and the whole event is over in half a
    /// second — which is all it has to be, since what it answers ("did that catch
    /// where I was pointing?") is answered by the first frame.
    ///
    /// **And it turns a quarter as it goes** (`markerSpin`), because a scope
    /// coming down on a spot is not only getting bigger. The bloom alone is a
    /// shape growing straight out of the pointer, which on a busy screen — a
    /// terminal repainting, a page scrolling under the shot he just took — is
    /// the one kind of motion the eye is worst at picking out; a rotation is
    /// not, and it costs no extra pixels and no extra time. It ends on the
    /// mark's own orientation, so nothing is left tilted (see `markerSpin`).
    static func markCursor(at point: NSPoint, duration: CFTimeInterval = markerDuration) {
        let reticle = CursorMarker.makeLayer(box: reticleBox)
        let side = reticle.bounds.width
        // The window has to hold the mark at its **largest**, or the bloom is
        // clipped by its own panel a third of the way out.
        let grown = (side * markerEndScale).rounded(.up)
        let frame = NSRect(x: point.x - grown / 2, y: point.y - grown / 2, width: grown, height: grown)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        reticle.position = CGPoint(x: grown / 2, y: grown / 2)
        view.layer?.addSublayer(reticle)

        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        activePanels.append(panel)

        reticle.transform = CATransform3DMakeScale(markerEndScale, markerEndScale, 1)
        // **One animation on `transform`, not one per component.** The spin and
        // the bloom are two readings of the same matrix, and `transform.scale`
        // beside `transform.rotation.z` is two animations each computing the
        // whole matrix from the model value — they overwrite each other rather
        // than compose. Core Animation interpolates a `CATransform3D` by
        // decomposing it, so a rotate-and-scale pair travels as a rotate and a
        // scale and never shears.
        let zoom = CABasicAnimation(keyPath: "transform")
        zoom.fromValue = CATransform3DConcat(
            CATransform3DMakeScale(markerStartScale, markerStartScale, 1),
            CATransform3DMakeRotation(-markerSpin, 0, 0, 1))
        zoom.toValue = CATransform3DMakeScale(markerEndScale, markerEndScale, 1)
        zoom.duration = duration
        // Fast out of the gate and slow at the edge: a bloom decelerating as it
        // spreads reads as something released, where a linear one reads as
        // something being pushed.
        zoom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        zoom.fillMode = .forwards
        zoom.isRemovedOnCompletion = false
        reticle.add(zoom, forKey: "zoom")

        let life = CAKeyframeAnimation(keyPath: "opacity")
        // **Half, not 80%.** The reticle is drawn over whatever he is talking
        // about — routinely the very line or button he is describing — so the
        // louder it is, the more of the thing it points at it hides. At 0.5 it is
        // still the first thing the eye finds (nothing else on that screen is
        // yellow and moving) while the pixels underneath stay readable, which
        // matters because the reason it is on screen is so a mis-aimed shot can
        // be noticed and retaken while the sentence is still being spoken.
        // Held only long enough to be seen at all, then gone: the fade rides the
        // same half second as the bloom, so the mark is at its faintest exactly
        // when it is at its widest and covering the most.
        life.values = [0.5, 0.45, 0.0]
        life.keyTimes = [0.0, 0.35, 1.0]
        life.duration = duration
        life.fillMode = .forwards
        life.isRemovedOnCompletion = false
        view.layer?.add(life, forKey: "life")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            panel.orderOut(nil)
            activePanels.removeAll { $0 === panel }
        }
    }

    /// Roughly what the Addons reticle covers on his display — that one is
    /// `makeSniperReticle(scale: 1.25)` over a 65pt base.
    private static let reticleBox: CGFloat = 81
    /// Half a second, start to finish.
    static let markerDuration: CFTimeInterval = 0.5
    /// Where the bloom starts and ends, against the mark's drawn size. The end is
    /// ~4× the old resting 0.9×, which is what Victor asked for.
    private static let markerStartScale: CGFloat = 0.5
    private static let markerEndScale: CGFloat = 3.6
    /// A **quarter turn**, spent entirely on the way out — Victor's number.
    ///
    /// 90° is the one angle this shape can be turned by and still be itself: a
    /// ring, four arms and a dot are four-fold symmetric, so the mark lands
    /// exactly on its own drawing and nothing is left sitting askew over his
    /// work. It is therefore read as *motion* and never as *orientation* — the
    /// spin makes the target catch the eye while it is happening and says
    /// nothing once it is over, which is the same bargain the bloom strikes.
    ///
    /// It runs backwards, from −90° to 0, so the resting transform stays the
    /// plain scale it always was.
    private static let markerSpin: CGFloat = .pi / 2

    /// The screen the cursor is on — the one that was just captured.
    static func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

extension NSColor {
    /// The one colour that means "the relay just photographed this".
    ///
    /// **Lifted from `victor-macos-addons`, where ⌃P has meant it for years.**
    /// That desktop already draws this exact border around the screen when it
    /// takes a picture, and Victor watches both apps on the same Mac — two
    /// different colours for the same event is a distinction that has to be
    /// learned and buys nothing. It replaces `systemRed`, which was doing double
    /// duty: red is also how every UI on that screen says *error*, and a red
    /// border thrown across the display at the moment a dictation starts reads as
    /// something going wrong for the fraction of a second before it is recognised.
    ///
    /// `systemYellow` is the literal value there — its own code calls it "the
    /// yellow border" — and it renders as the amber Victor calls orange.
    static var captureAccent: NSColor { .systemYellow }
}
