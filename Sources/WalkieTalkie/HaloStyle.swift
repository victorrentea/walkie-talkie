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
    /// Page 1, *Bipolar* — the first preset the page lists (*"MilkDrop
    /// 1/103"*), asked for by name on 2026-09-21. Shipped with MilkDrop 2 and
    /// bundled with butterchurn as JSON; the original `.milk` came from
    /// projectM's `presets_milkdrop_200`, so nothing was converted.
    case milkdrop1
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
        case .milkdrop1:      return "Bipolar"
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
        // Bipolar: a feedback preset — a thick waveform whose trail is pushed
        // outward at the centre and pulled inward at the rim
        // (`zoom = 0.9615 + 0.1*rad`), so its composition fills the canvas the
        // way Tunnel's does and fades at the canvas edge rather than at a
        // radius. Its frame code does not move `cx`/`cy`, so nothing to pin.
        case .milkdrop1:   return Preset(number: 1, name: "Geiss - Bipolar 2 Enhanced", scale: 0.75,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0)
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
        case .milkdrop8:   return Preset(number: 8, name: "Geiss - Cauldron - painterly 2 (saturation remix)", scale: 0.525,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0, pinCenter: true)
        case .milkdrop20:  return Preset(number: 20, name: "Aderrasi + Geiss - Airhandler (Kali Mix) - Painterly Tendrils Colorfast", scale: 0.728,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0)
        case .milkdrop85:  return Preset(number: 85, name: "Zylot - Star Ornament", scale: 0.69,
                                         fade: true, fadeAtEdge: true, fadeFloor: 0)
        case .milkdrop87:  return Preset(number: 87, name: "martin - chain breaker", scale: 0.75,
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
    /// Snowflake is off it too, temporarily (Victor, 2026-09-20: *"scoate
    /// temporar din meniu/din efecte Snowflake"*); the preset stays in place.
    /// Pulse went the same evening (*"scoate pulse"*), after its fog came back
    /// down to 1×; the page still draws it.
    /// The menu, the dial, F7/F9 and `/test/halo` read this list; a saved
    /// preference off it reads as the film.
    var isOffered: Bool { self != .milkdrop103 && self != .milkdrop85 && self != .waveRing }
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
    static let defaultsKey = "haloStyle"

    static var current: HaloStyle {
        if let name = ProcessInfo.processInfo.environment["WT_HALO_STYLE"],
           let forced = HaloStyle(rawValue: name) { return forced }
        guard let name = UserDefaults.standard.string(forKey: defaultsKey),
              let saved = HaloStyle(rawValue: name), saved.isOffered else { return .lightning }
        return saved
    }

    static func save(_ style: HaloStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: defaultsKey)
    }
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
