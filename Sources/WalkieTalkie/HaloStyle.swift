import AppKit
import Foundation

/// **Which effect is drawn round the pointer.** `.lightning` is the film
/// `CaretHalo` has always drawn, natively, and the one he uses all day. The
/// hand-written effects of the `voice-halo` page are run **by the page
/// itself** in a web view (`HaloPage`, 2026-09-20); the MilkDrop presets by
/// the real engine in another (`MilkDropHalo`, `assets/milkdrop/halo.html`).
/// Before that, nine effects were re-drawn in CoreGraphics
/// (`HaloEffects.swift`, tags `swift-port-01/02`); they came out small and
/// coarse and could not be made otherwise at the screen's resolution (a
/// full-screen CoreGraphics trail pass measured 48–86 ms a frame), so they went.
///
/// **The names are Victor's** (2026-09-20, the page's `name` field; the old
/// descriptions moved to `desc`): `Eclipse` and `Water Dream` are his own
/// words. A `−` on the page (Petals, Silk, Nova, Royal, Mosaic) is not here;
/// neither is the page's `Lagoon` (the hand-drawn water) — *"drop those
/// hand-drawn meteors — go back to the MilkDrop variant"*: Water Dream is the
/// water on the desktop.
///
/// `pageIndex` is the effect's position in the page's `FORMULAS` list — what
/// `halo.pick` takes. The page never reorders that list (its own rule), and
/// `HaloPage` logs the name the page answers with, so a drift would show in
/// the log on the first pick.
enum HaloStyle: String, CaseIterable {
    /// **What ships and what he uses every day** — the rotating lightning film
    /// in `CaretHalo`. Native, never waits on a web view.
    case lightning
    /// Page 1, *Pulse*: inel de undă — cerc perfect în tăcere, se rotește.
    case waveRing
    /// Page 2, *Amethyst*: oscilogramă mov — albastrul și roșul suprapuse.
    case oscillogram
    /// Page 3, *Crown*: coroană — numai barele, fără cerc fix.
    case crown
    /// Page 4, *Prism*: inel de segmente — nuanța se închide fără cusătură.
    case segments
    /// Page 5, *Eclipse*: lanț de fulgere — lasă valuri de ceață în urmă.
    case lightningChain
    /// Page 6, *Atom*: orbite rare — gaură mare, blocuri clare.
    case orbits
    /// Page 19, *Beads*: inel de blocuri — cerc în repaus, crește doar în afară.
    /// Listed before Gemini (Victor, 2026-09-20: *"beads: before gemini"*) —
    /// the menu, the dial and F7/F9 walk this order, not the page's.
    case blockBeads
    /// Page 7, *Gemini*: două bile — ceață suflată din contur spre exterior.
    case twoBalls
    /// **The MilkDrop presets pinned on the page** (chips 9, 10, 11, 14, 15,
    /// 18), run by the real engine. 99 (*Mosaic*) went on 2026-09-20 — *"the
    /// bricks look lame"* — with the other `−` ones. The numbers are the
    /// presets' numbers on the page, not the chips'.
    /// **Bipolar (page 1) was here for one evening and went, 2026-09-21.** Asked
    /// for by name in the morning — *"efectul 1 MilkDrop precedent"* — and
    /// rejected on sight the same night: *"acest efect nu îmi place, scoate-l de
    /// tot"*. It never looked right natively either (`docs/projectm/REPORT.md`
    /// item 11: 0.75–0.89% of the canvas lit, the circular waveform and none of
    /// the feedback trails the preset is known for), so nothing was tuned before
    /// it went. `git show` on this commit brings back the case, the `Preset` row
    /// and the `.milk`.
    case milkdrop7, milkdrop8, milkdrop20, milkdrop85, milkdrop87, milkdrop99, milkdrop103

    /// The menu row's wording — Victor's short names.
    var title: String {
        switch self {
        case .lightning:      return "Lightning ring"
        case .waveRing:       return "Pulse"
        case .oscillogram:    return "Amethyst"
        case .crown:          return "Crown"
        case .segments:       return "Prism"
        case .lightningChain: return "Eclipse"
        case .orbits:         return "Atom"
        case .twoBalls:       return "Gemini"
        case .blockBeads:     return "Beads"
        case .milkdrop7:      return "Tunnel"
        case .milkdrop8:      return "Cauldron"
        case .milkdrop20:     return "Tendrils"
        case .milkdrop85:     return "Snowflake"
        case .milkdrop87:     return "Sparks"
        case .milkdrop99:     return "Mosaic"
        case .milkdrop103:    return "Water Dream"
        }
    }

    /// Victor's review mark, as the page carries it in the effect's name
    /// (`★` likes a lot, `•` has potential). A `−` is never here, because a
    /// `−` effect is not offered.
    var mark: String {
        switch self {
        case .milkdrop7, .milkdrop20:  return "•"
        case .milkdrop87, .milkdrop103: return "★"
        default:                        return ""
        }
    }

    /// **The menu shows the name and nothing else** (Victor, 2026-09-20 late:
    /// *"don't put stars or dots in the menu in the effect names any more,
    /// just a lightning bolt after their name"*): the verdict marks stay on
    /// the page, where they are recorded; a preset's bolt is a symbol the
    /// menu appends (`StatusItem.applyHaloRow`), not part of the title.
    var menuTitle: String { title }

    /// **The effect's position in the page's `FORMULAS`** — what `halo.pick`
    /// takes. Nil for the film and for the presets (the engine's page takes
    /// the preset's name instead).
    var pageIndex: Int? {
        switch self {
        case .waveRing:       return 0
        case .oscillogram:    return 1
        case .crown:          return 2
        case .segments:       return 3
        case .lightningChain: return 4
        case .orbits:         return 5
        case .twoBalls:       return 6
        // 7 is `− Petals`; 8…17 the presets; 19 `Lagoon`, dropped
        case .blockBeads:     return 18
        // Water Dream's comets (`comets.js`), drawn over the pinned preset
        case .milkdrop103:    return 20
        default:              return nil
        }
    }

    /// **A preset run by the engine**: the page's `preset:` row. `scale`
    /// shrinks the canvas on screen (the composition intact) — the page's
    /// values, halved on 2026-09-20 with the rest, then resized on sight the
    /// same evening: Snowflake ×4 (*"much too small"*), Tendrils ×2, Sparks
    /// ×1.5, Tunnel ÷3 then ×2.5 then ×2 (0.84), Cauldron ×1.5 (0.525). `fade` is the radial
    /// dimming, and the rest are Victor's asks on Tunnel that day: *"de 2x mai
    /// opac/intens … fade out complet la o distanță de 1/2 din width ecran
    /// (adică să se răspândească mai mult pe ecran)"* plus *"2x more
    /// rotation"* — so Tunnel keeps the full canvas, fades to nothing at half
    /// the screen's width from the pointer, at twice the intensity and twice
    /// the turn. See `halo.html`'s `preset(name, fade, opts)`.
    ///
    /// **No square, anywhere** (Victor, 2026-09-20: *"it still renders effects
    /// with a square crop around them"*): a preset's canvas *is* its
    /// composition, so a scaled-down one that paints to its border would show
    /// an edge. Every scaled preset therefore fades radially to nothing at its
    /// canvas edge (`fadeAtEdge`); Tunnel fills the whole canvas and fades at
    /// half the screen's width instead.
    struct Preset {
        let number: Int; let name: String; let scale: CGFloat
        var fade = false; var fadeRadius: CGFloat? = nil; var fadeAtEdge = false; var fadeFloor: CGFloat = 0.10
        var gain: CGFloat = 1; var rot: CGFloat = 1
        /// Full light out to this fraction of the fade radius, then one smooth
        /// fall to `fadeFloor`; 0 = the page's four-stop mask.
        var fadeStart: CGFloat = 0
        /// The point of the canvas that sits on the pointer, as fractions of
        /// its side, y down (the preset's own centre of composition — `cx`/`cy`
        /// in its frame equations). Default the middle.
        var centerAt: CGPoint = CGPoint(x: 0.5, y: 0.5)
        /// A fixed shift of the whole canvas from the pointer, in points, y up
        /// (Cocoa). Tunnel sits 50 pt above it (Victor, 2026-09-20).
        var offset: CGPoint = .zero
        /// Append `a.cx = a.cy = 0.5` to the preset's frame equations, so a
        /// composition that drifts its own centre stays on the pointer.
        var pinCenter = false
        /// Pinned to the screen (not following the pointer), the canvas's
        /// centre — the preset's horizon — at this fraction of the screen's
        /// height from the bottom. Nil = the square follows the pointer.
        var pinnedHorizon: CGFloat? = nil
        /// **This preset is drawn by butterchurn whichever engine is picked.**
        /// Not a preference and not a fallback: a preset whose *look* depends on
        /// how the engine reads the spectrum, where the two engines disagree and
        /// the web one is the picture Victor approved. It lives here, beside the
        /// preset's other knobs, because the alternative — a preset number
        /// compared by hand at each of the two places that decide — is a fact
        /// kept in two heads. `CaretHalo.engineHost` and `isAvailable` both read
        /// it, and nothing else may branch on a preset number.
        var webOnly = false
        /// **How fast the preset's own clock runs**, 1 = real time. Presets are
        /// written in *time* (`time`, `fps` in their equations), not in frames,
        /// so the frame cap cannot slow one down — it only makes it choppier.
        /// This is butterchurn's own `render({elapsedTime})`, i.e. the engine
        /// being told how much of its second has passed: at 0.6 the animation
        /// takes 1.67 s to do what it did in 1 s, at the same frame rate.
        ///
        /// **Honoured by the web route only.** `ProjectMHalo` says so in the log
        /// rather than ignoring it quietly, and a preset that sets `speed`
        /// should carry `webOnly` with it.
        var speed: CGFloat = 1
        /// **Canvas pixels per point** — nil = the display's backing scale, one
        /// canvas pixel per device pixel, which is right for every preset but
        /// one.
        ///
        /// **It is not a quality dial, it is a feature-size dial** (2026-09-21,
        /// Victor on Sparks after the 1:1 fix: *"parcă tot puncte cețoase
        /// văd"*). A MilkDrop preset's features are not a constant fraction of
        /// its canvas: measured on the same 10 % of the canvas at the same
        /// second of the same clip, a chain-breaker spark is ~5 canvas px at
        /// 1610, ~20 at 3220 and ~56 at 6440 — **it grows faster than the
        /// canvas does**, so more pixels means bigger, softer, more crowded
        /// sparks that merge into the wash he called fog. Fewer pixels means
        /// small, separate stars. The screen captures are in
        /// `docs/projectm/captures/sparks-resolution-2026-09-21/`.
        ///
        /// So the halo can be big and its sparks small only by rendering the
        /// canvas coarser than the screen and letting the compositor scale it
        /// up. Keep the ratio an exact integer — 1 pt = 2 device px here — so
        /// the upscale is the gentlest one there is; a fractional one is the
        /// blur this file spent the evening removing.
        /// `WT_MD_SCALE` overrides it for a run.
        var renderScale: CGFloat? = nil
    }
    var preset: Preset? {
        switch self {
        // **×0.7 on 2026-09-21 evening** (*"circumferința interioară să fie cu 30 %
        // mai mic și să fie mai pregnant vizibil pe ecran"*): 0.84 → 0.588, so the
        // ring hugs the pointer closer. It pays for itself twice — a smaller
        // canvas is fewer engine pixels, so the preset's structures are thicker
        // relative to it, which is most of the brightness the move to the backing
        // scale had cost. The other half is `ProjectMHalo.gainScale[7]`, and the
        // reasoning for both numbers is written out there.
        //
        // Tunnel: *"3x smaller"* than what he saw (the full-screen canvas), so a
        // third of the screen's long side; its fade is the canvas edge now (the
        // half-screen radius would be outside it), at his 2× gain and 2× turn.
        // *"Tunnel 2x more visible"*: measured, gain 3 or 4 changes nothing the
        // key can show (the bright parts are at 1 already) — what dims Tunnel is
        // the mask, half-light at half the radius. So: full light out to 55 %
        // of the radius, then one fall to nothing at the edge; gain 4 as asked.
        case .milkdrop7:   return Preset(number: 7, name: "Geiss - 3 layers (Tunnel Mix)", scale: 0.588,
                                         // *"appears centred slightly below the mouse"*, then *"no longer
                                         // centred"* after a static offset: the preset's centre WANDERS —
                                         // its frame code adds ±0.11 of sine terms to cx/cy every frame —
                                         // so the wander is pinned out of our copy (`pinCenter`) instead.
                                         fade: true, fadeAtEdge: true, fadeFloor: 0, gain: 4, rot: 2, fadeStart: 0.55,
                                         offset: CGPoint(x: 0, y: 50), pinCenter: true)
        // **Cauldron needs `gain: 6` to be seen at all** (2026-09-21). It came
        // out of the catalogue at the default 1 and nobody had worn it for a
        // whole dictation until it became Wispr's dress; Victor's report was
        // *"nu vad nici o animatie"*, and a capture of the real panel
        // (`WT_HALO_DEMO`, the only path that is screenshottable) showed why —
        // at 1 it is a smudge a shade off the terminal behind it, at 3 still
        // nothing, at 6 a cyan bloom that reads. Same knob and same reason as
        // Tunnel's `gain: 4`: `ProjectMHalo.gainScale` is a *calibration*
        // between the two engines (0.3 here, measured against the web twin's
        // luminance) and must not be moved to make a preset brighter — this is
        // the per-style brightness, and it is applied in both engines.
        case .milkdrop8:   return Preset(number: 8, name: "Geiss - Cauldron - painterly 2 (saturation remix)", scale: 0.525,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0, gain: 6, pinCenter: true)
        // Tendrils ×0.7 on sight (Victor, 2026-09-21: *"tendrils să fie .7x
        // mărime (mai mic)"*) — 0.728 → 0.51, the same move Sparks got the
        // evening before — and ×0.7 again the same morning, together with
        // Sparks (*"micșorează la 0.7x și pentru efectul cu dictarea
        // legată"*): 0.51 → 0.357. The page's own `FORMULAS` entry still says
        // 0.728; the number the app draws at is this one.
        case .milkdrop20:  return Preset(number: 20, name: "Aderrasi + Geiss - Airhandler (Kali Mix) - Painterly Tendrils Colorfast", scale: 0.357,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0)
        case .milkdrop85:  return Preset(number: 85, name: "Zylot - Star Ornament", scale: 0.69,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0)
        // **Sparks' size is a chain of factors, each one applied to what was
        // drawn at the time** — never to the page's `FORMULAS` 0.75 (Victor,
        // 2026-09-20/21):
        //   0.75 ×0.7 ×0.7 → 0.3675  two *"mai mic cu treizeci la sută"*, asked
        //                            while the destinations were still moving
        //   ×3   → 1.1025            *"the stars effect … should be three times
        //                            larger … very similar to what I want"*,
        //                            asked of it wearing the destination it
        //                            keeps; 1905 pt, wider than the screen
        //   ×0.5 → 0.55125           *"efectul de stars e prea mare.
        //                            Micșorează-l cu cincizeci la sută"*
        //   ×1.3 → 0.716625          *"fa stars mai mare cu 30%"*
        //   ×1.3 → 0.9316125         the same sentence again, minutes later;
        //                            1610 pt on the built-in retina
        //   ×0.5 → 0.46580625        *"redu efectul stars la 50% dimensiune
        //                            (vocea mai puternică îl triggerează mai
        //                            bine)"* — and the parenthesis is the whole
        //                            reason: the two ×1.3 above were asked
        //                            while macOS's input volume was down on the
        //                            built-in microphone, so Sparks was being
        //                            fed a third of the signal it is written
        //                            for and he was enlarging a faint thing to
        //                            see it. With the slider back up it
        //                            triggers properly and wants to be small
        //                            again — which lands it near the 0.55125 it
        //                            had before the two enlargements
        // The last three are him homing in by eye on a thing that only exists
        // while it is running. Since the halving the direction has been one
        // way, so multiply **this** number for the next ask: do not average the
        // sequence and do not reach back to an earlier entry in it.
        // **The pt figures above are the square the halo really occupies only
        // from the last of them.** Until that evening `halo.html` scaled its
        // canvas by `scale` a second time, on a view `panelFrame` had already
        // scaled, so the web route drew `max(w, h) × scale²` and every ask
        // landed **squared** — the ×3 was ×9 on screen. That is most of why it
        // took five asks to find a size. Sparks went 1500 → 1610 pt when the
        // second scale went, `scale` is linear from here, and the native engine
        // had always been linear (`ProjectMHalo` never scaled twice).
        // **"Not centred on the tip of my mouse" was a size complaint, and the
        // composition already is centred** — measured, not argued: the demo on
        // his own screen with the pointer in frame, each halo capture
        // differenced against a baseline capture of the same desktop, gives the
        // cloud's centre of light within ~10 pt of the tip over four frames
        // (`docs/projectm/captures/sparks-on-pointer-2026-09-21.png`, the
        // crosshair is the tip). What was wrong is the size: a ~160 pt knot in
        // a 635 pt canvas leaves the pointer sitting at the edge of the bright
        // part rather than inside it, and a knot that wanders frame to frame
        // reads as off-centre. So reach for `scale`, and leave
        // `centerAt`/`offset` at their defaults — a static shift on a
        // composition that is already centred is what made Tunnel *"no longer
        // centred"* in the other direction.
        // **Sparks is drawn by butterchurn even when the engine is projectM**
        // (`webOnly`, 2026-09-21: *"Stars nu arată cum arată originalul … linia
        // aia e prea lăbărțat"*). chain breaker offsets spark *n* by a smoothed
        // difference of spectrum bins *n* and *n+dif*, so the shape of the
        // effect is a property of the **spectrum's smoothness**, not of any knob
        // here: projectM FFTs 480 Hann-windowed samples zero-padded to 1024 and
        // its neighbouring bins agree (measured r = 0.90 on his own speech), so
        // the 256 sparks land next to each other and string into a chain;
        // butterchurn FFTs 1024 raw samples with no window, its bins are
        // independent (r = 0.32), and the sparks scatter into the cloud he
        // starred. Measured across `PM_SPECTRUM_SCALE` 1…5.3, with `rand()` and
        // `fps` forced, and against the same gain in both engines — a chain
        // never becomes a cloud (`docs/projectm/captures/sparks-2026-09-21/`).
        // Worth knowing before anyone "fixes" this back: real MilkDrop windows
        // its FFT too, so the chain is arguably the preset's intended look and
        // the cloud is butterchurn's deviation. The cloud is the one he picked.
        // **Sparks renders at 1 canvas pixel per point, half the screen's own
        // resolution** — see `Preset.renderScale`. It is the one preset whose
        // sparks were merging into a wash at 1:1, and the only one that asks
        // for this.
        case .milkdrop87:  return Preset(number: 87, name: "martin - chain breaker", scale: 0.46580625,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0, webOnly: true,
                                         renderScale: 1)
        // **Mosaic, back from the `−` list for Wispr Flow** (Victor, 2026-09-21:
        // *"când am Wispr Flow, dictare să apară mozaic"*). It was dropped on
        // 2026-09-20 with the other `−` effects — *"the bricks look lame"* —
        // and is here now because he asked for it by name against a
        // destination, which is a different question from *do I like it in a
        // gallery*.
        //
        // **×1.5, slower, brighter, and butterchurn's** (2026-09-21 evening:
        // *"mozaicul … trebuie să fie de 1.5 ori mai mare și mai intens, puțin
        // mai lent, să pot să văd acele animații cum se mișcă. Am impresia că,
        // în animația originală, mai avea și alte efecte decât aceasta,
        // comparativ cu cea din web"*). The last sentence is the one that
        // decides the engine: he is right, and it had been measured before he
        // said it — natively each tile is a large smooth lens blob with thick
        // dark seams, where butterchurn draws small tiles with fine swirl
        // interiors and the crisp coloured `wave_0` dots. Rendering at the
        // backing scale fixed the *size* of the tiles and not their insides,
        // and the remaining difference is engine dynamics rather than a knob
        // (`docs/projectm/captures/mosaic-2026-09-21/`). So `webOnly`, the same
        // move Sparks needed for the same kind of reason.
        //
        // 0.5 → 0.75 is his ×1.5; `speed` 0.6 is *"puțin mai lent"*, which the
        // frame cap cannot do (see `Preset.speed`).
        case .milkdrop99:  return Preset(number: 99, name: "martin - reflections on black tiles", scale: 0.75,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0, gain: 1,
                                         webOnly: true, speed: 0.6)
        // **Water Dream is a hybrid** (Victor, 2026-09-20 late: *"the water stays
        // locked in the bottom 20% of the screen, but the meteors follow the
        // mouse"*): the preset gives the sky and the pool, pinned to the screen
        // with its horizon at the pool's edge (`pinnedHorizon`), and the page's
        // `Comets` effect orbits the pointer above it, reflected into the pool.
        // A canvas 1.1× the screen's long side covers the screen with the
        // horizon at 20 %. Mac only: on the phone page the presets render dark
        // in embed, so there Water Dream is the preset alone.
        // *"water dream is too violent"* (the same evening): the light at 0.6.
        // `POST /test/halo {"style": "milkdrop103", "opts": {"gain": 0.4}}` is
        // how the next number gets looked at without a rebuild.
        case .milkdrop103: return Preset(number: 103, name: "martin [shadow harlequins shape code] - fata morgana", scale: 1.1,
                                         gain: 0.6, pinnedHorizon: 0.20)
        default:           return nil
        }
    }

    var isPreset: Bool { preset != nil }

    /// **On the list today.** Water Dream is off it *"for the moment"*
    /// (Victor, 2026-09-20 late — the dearest style measured, 0.79 of a GPU
    /// core and 866 MB, and still "too violent"); its hybrid stays built.
    /// Snowflake is off it too (Victor, 2026-09-20: *"scoate temporar din
    /// meniu/din efecte Snowflake"*). It came back for a few hours on
    /// 2026-09-21, on the reading that it was the dress of a sentence opening
    /// a new claude — and that reading was wrong (*"la dictarea in terminal
    /// nou, sa redai efectul stars, nu snowflake"*), so the row goes with it.
    /// Nothing wears it now, and a style no destination wears has no claim on
    /// the menu.
    /// Pulse went the same evening (*"scoate pulse"*), after its fog came back
    /// down to 1×; the page still draws it.
    /// The menu, the dial, F7/F9 and `/test/halo` read this list; a saved
    /// preference off it reads as the film.
    /// Gemini too (2026-09-21, *"scoate gemini din opțiuni"*).
    var isOffered: Bool { self != .milkdrop103 && self != .milkdrop85 && self != .waveRing && self != .twoBalls }
    static var offered: [HaloStyle] { allCases.filter { $0.isOffered } }

    /// A page effect drawn on an opaque canvas the page keys to alpha in WebGL.
    /// None today (the water went); kept because `HaloPage` refuses such an
    /// effect without WebGL rather than putting a black rectangle on screen.
    var needsWebGL: Bool { false }

    /// **Drawn on a panel the size of the pointer's screen**: every page
    /// effect. The page lays out from the viewport, several effects run to
    /// its edge by design, and the pointer is handed in as the origin rather
    /// than the window moved (Victor: *nothing may clip; no artificial scaling*).
    var coversScreen: Bool { pageIndex != nil }

    /// Both web views at once: the pinned preset underneath, the page on top.
    var isHybrid: Bool { pageIndex != nil && preset != nil }

    /// Can this style be drawn on this Mac right now? The film always; a page
    /// effect when the page is bundled; a preset when the engine is too.
    var isAvailable: Bool {
        if pageIndex != nil { return HaloPage.available }
        if let preset = preset {
            // A `webOnly` preset needs the web engine to exist, whichever engine
            // is picked — see `Preset.webOnly` and `CaretHalo.engineHost`.
            return HaloEngine.current == .native && !preset.webOnly ? ProjectMHalo.available(for: preset) : MilkDropHalo.engineAvailable
        }
        return true
    }

    /// Why a row is greyed, for the menu.
    var unavailableReason: String? {
        guard !isAvailable else { return nil }
        return isPreset ? "engine not bundled" : "page not bundled"
    }

    /// **Persisted like the app's other preferences**: `UserDefaults`, not
    /// `~/.walkie-talkie` — it is a preference, not data, and `--home` has no
    /// business moving it. `WT_HALO_STYLE=<case>` overrides it for one run, the
    /// way `WT_HALO_DESIGN` does for the film's texture. A saved style that no
    /// longer exists (the water, Mosaic) reads as the film.
    ///
    /// **Three preferences since 2026-09-21, one per destination** — see
    /// `HaloDestination`. The single old key (`haloStyle`) is no longer read:
    /// it held one answer to a question that now has three, and the three
    /// defaults Victor asked for are better than any migration of it.
    static func current(for destination: HaloDestination) -> HaloStyle {
        if let name = ProcessInfo.processInfo.environment["WT_HALO_STYLE"],
           let forced = HaloStyle(rawValue: name) { return forced }
        guard let name = UserDefaults.standard.string(forKey: destination.defaultsKey),
              let saved = HaloStyle(rawValue: name), saved.isOffered else { return destination.fallback }
        return saved
    }

    /// What is drawn before the first dictation of the session says where it is
    /// going — the caret's, because an unbound sentence is the common case.
    static var current: HaloStyle { current(for: .caret) }

    static func save(_ style: HaloStyle, for destination: HaloDestination) {
        UserDefaults.standard.set(style.rawValue, forKey: destination.defaultsKey)
    }
}

/// **Where the sentence being dictated is headed** — and therefore which
/// effect is drawn round the pointer while it is being said.
///
/// Victor, 2026-09-21: *"tunnel să fie la dictarea la caret … tendrils dacă
/// sunt legat și sparks dacă dictez în terminal nou"*, then *"mi-ar plăcea să
/// pot alege separat cele trei efecte"*. One preference per destination rather
/// than one for the app: the ring is already the only thing on screen while he
/// talks, and the destination is the one fact about a dictation that he cannot
/// otherwise see without looking away from the pointer.
///
/// `AppDelegate.syncBorrowedGestures` decides which of the four a dictation is
/// — the same expression that decides `atCaret`, plus `spawnPending` and
/// `foreignMic` — and pushes it into `CaretHalo.setDestination` on the edge
/// that raises the ring.
enum HaloDestination: String, CaseIterable {
    /// Replace Wispr and an unbound sentence — **this app's** microphone typing
    /// where the caret is, whatever it is bound to.
    case caret
    /// ⌘⌃B was pressed: the words are typed into the bound terminal.
    case bound
    /// `Start dictation to new claude` — the sentence opens a terminal of its own.
    case spawn
    /// **A dictation Wispr Flow is running on its own** — right ⌘⌥ held, or
    /// fn ⌃ Space: the relay rings for it and routes nothing (`relay: false`).
    ///
    /// It wore the caret's dress until 2026-09-21 (*"Wispr Flow, când
    /// dictează, să fie dictare la caret"*, which was about the **destination**
    /// — Wispr types at the caret — and was read as being about the effect too).
    /// Victor separated the two the same day: *"Wispr-ul este o dictare … la fel
    /// de dictare. Folosește un efect MilkDrop rămas pentru el"*. A foreign
    /// microphone is worth telling apart on sight, because it is the one kind of
    /// sentence none of this app's gestures apply to — no shot, no pick, no
    /// arrow, nothing to hang on it.
    case wispr

    /// The menu row's wording, in the menu's own vocabulary.
    var title: String {
        switch self {
        case .caret: return "At the caret"
        case .bound: return "Bound terminal"
        case .spawn: return "New claude"
        case .wispr: return "Wispr Flow's own"
        }
    }

    /// **Victor's picks of 2026-09-21**, and what an unset preference reads as.
    /// Not the film: he named a preset for each.
    ///
    /// `wispr` gets **Cauldron**, which is *"un efect MilkDrop rămas"* quite
    /// literally: of the six presets on the page it is the only one still
    /// offered in the menu that none of the other three had claimed (Snowflake
    /// and Water Dream are built but off the list).
    var fallback: HaloStyle {
        switch self {
        // **Tunnel and the caret parted on 2026-09-21** (*"schimbă între ele
        // efectul de la dictarea la caret și dictarea legată; inversează-le pe
        // cele două"*). What was swapped is what he had **running** — Tunnel at
        // the caret, Tendrils bound, the latter his own pick over the Cauldron
        // that used to be this line — so both fallbacks are written to the
        // arrangement after the swap and the two stored preferences with them.
        // The caret is the destination he sees most, and Tunnel is the preset
        // that spent the evening needing his voice louder than it is.
        case .caret: return .milkdrop20   // Tendrils
        case .bound: return .milkdrop7    // Tunnel
        // **Sparks — and "stars" never meant Snowflake** (Victor, 2026-09-21,
        // correcting the same day's guess: *"la dictarea in terminal nou, sa
        // redai efectul stars, nu snowflake"*). Sparks had held this
        // destination and was taken off it that morning by reading *stars* as
        // a **name** and matching it to the only preset in the catalogue with
        // a star in its title — Zylot's *Star Ornament*, which the menu calls
        // Snowflake. The pictures say why that was wrong, and they were on
        // disk the whole time (`docs/projectm/captures/`): Star Ornament draws
        // **one large five-pointed ornament**, a snowflake; chain breaker
        // draws **a cloud of small bright points**, which is what a man
        // looking at his pointer calls stars. He was describing a picture, not
        // naming a row.
        //
        // The general rule, since it has now cost two rounds: a destination's
        // dress is named by what it **looks like**. When his word does not
        // match a menu title exactly, look at `docs/projectm/captures/` before
        // matching on the title — `docs/projectm/shoot.sh <outdir> <styles>`
        // makes the picture for one that has none.
        //
        // It keeps the 0.7× of that morning (0.3675); Snowflake goes back off
        // the offered list, where *"scoate temporar din meniu/din efecte
        // Snowflake"* had put it — it was only relisted because a destination
        // wore it, and none does now.
        case .spawn: return .milkdrop87   // Sparks
        // **Mosaic** (*"când am Wispr Flow, dictare să apară mozaic"*) —
        // brought back from the page's `−` list for this one destination.
        case .wispr: return .milkdrop99   // Mosaic
        }
    }

    var defaultsKey: String { "haloStyle.\(rawValue)" }
}

/// **The frame cap for every web view** (Victor, 2026-09-20: *"30 is more
/// than enough … I'll probably only run these effects on battery"*): the
/// pages' per-frame constants are time-based, so 30 looks like 60 at half
/// the CPU. `WT_HALO_FPS=60` for a comparison run, `0` for no cap.
let haloFrameCap: Int = ProcessInfo.processInfo.environment["WT_HALO_FPS"].flatMap(Int.init) ?? 30

/// **What `CaretHalo` asks of a web view**, whichever page is in it: the
/// page's frame loop on and off with the ring, the microphone's samples, the
/// pointer, and a way to say it cannot go on (the film takes over).
protocol HaloWebHost: AppKit.NSView {
    var onFailure: ((String) -> Void)? { get set }
    /// The host has something on screen — the page's first pick answered, or
    /// the engine's warm-up is over and it is fading in. What retires the
    /// panel before it (`CaretHalo.rebuild`).
    var onVisible: (() -> Void)? { get set }
    func start()
    func stop()
    func feed(_ samples: [Float])
    func center(_ p: CGPoint)
}
