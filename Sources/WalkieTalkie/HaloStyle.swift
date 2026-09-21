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
    case milkdrop7, milkdrop8, milkdrop20, milkdrop85, milkdrop87, milkdrop103

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
    }
    var preset: Preset? {
        switch self {
        // Tunnel: *"3x smaller"* than what he saw (the full-screen canvas), so a
        // third of the screen's long side; its fade is the canvas edge now (the
        // half-screen radius would be outside it), at his 2× gain and 2× turn.
        // *"Tunnel 2x more visible"*: measured, gain 3 or 4 changes nothing the
        // key can show (the bright parts are at 1 already) — what dims Tunnel is
        // the mask, half-light at half the radius. So: full light out to 55 %
        // of the radius, then one fall to nothing at the edge; gain 4 as asked.
        case .milkdrop7:   return Preset(number: 7, name: "Geiss - 3 layers (Tunnel Mix)", scale: 0.84,
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
        // Sparks ×0.7 a second time (Victor, 2026-09-21: *"efectul care apare
        // când fac gestul de deschidere într-un terminal nou trebuie să fie
        // mai mic cu treizeci la sută"*) — 0.75 → 0.525 the evening before,
        // 0.525 → 0.3675 now. Each ask is a factor on what is drawn today, not
        // on the page's original, so the two compound.
        case .milkdrop87:  return Preset(number: 87, name: "martin - chain breaker", scale: 0.3675,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0)
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
    /// Snowflake was off it too (Victor, 2026-09-20: *"scoate temporar din
    /// meniu/din efecte Snowflake"*) — **temporarily**, and the temporary
    /// ended on 2026-09-21, when he made it the dress of a sentence opening a
    /// new claude (*"dictarea în terminal nou tre să redea efectul de
    /// stars"*): a destination's effect has to be pickable in the menu beside
    /// the other three, or its row is the one tick he cannot move.
    /// Pulse went the same evening (*"scoate pulse"*), after its fog came back
    /// down to 1×; the page still draws it.
    /// The menu, the dial, F7/F9 and `/test/halo` read this list; a saved
    /// preference off it reads as the film.
    /// Gemini too (2026-09-21, *"scoate gemini din opțiuni"*).
    var isOffered: Bool { self != .milkdrop103 && self != .waveRing && self != .twoBalls }
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
            return HaloEngine.current == .native ? ProjectMHalo.available(for: preset) : MilkDropHalo.engineAvailable
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
        case .caret: return .milkdrop7    // Tunnel
        case .bound: return .milkdrop20   // Tendrils
        // **Snowflake, since 2026-09-21** (*"dictarea în terminal nou tre să
        // redea efectul de stars"*) — Zylot's *Star Ornament*, which is the
        // only star in the catalogue. Sparks held this destination for a few
        // hours before it; it keeps the 0.7× he asked for that morning and
        // stays on the list, so the row is one tick away.
        case .spawn: return .milkdrop85   // Snowflake
        case .wispr: return .milkdrop8    // Cauldron
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
