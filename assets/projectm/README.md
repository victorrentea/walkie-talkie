# MilkDrop presets for the native halo (`ProjectMHalo`)

`presets/<butterchurn name>.milk` — the original MilkDrop 2 text of every preset
`HaloStyle.Preset` names, so the native engine draws the same composition the
web route draws from butterchurn's JSON conversion of the same file:

| style | file | source |
|---|---|---|
| Tunnel (7) | `Geiss - 3 layers (Tunnel Mix).milk` | clangen/projectM-musikcube `presets_milkdrop_200` |
| Cauldron (8) | `Geiss - Cauldron - painterly 2 (saturation remix).milk` | `~/workspace/milkdrop-gallery/sources/cream` |
| Tendrils (20) | `Aderrasi + Geiss - Airhandler (Kali Mix) - Painterly Tendrils Colorfast.milk` | clangen/projectM-musikcube `presets_milkdrop_200` |
| Snowflake (85) | `Zylot - Star Ornament.milk` | `milkdrop-gallery/sources/original` |
| Sparks (87) | `martin - chain breaker.milk` | `milkdrop-gallery/sources/cream` |
| Water Dream (103) | `martin [shadow harlequins shape code] - fata morgana.milk` | OfficialIncubo/BeatDrop-Music-Visualizer `resources/Milkdrop2/presets` |

`textures/` — what a preset's `sampler_<name>` asks for that is not built into
the engine (noise textures are). None of the six needs one today; `worms.jpg`
(projectM's `presets-milkdrop-texture-pack`) is kept from the spike's stand-in
for Water Dream, `martin - golden mirror`.

`build-app.sh` should copy this folder to `Resources/projectm` (not wired on the
`projectm` branch — the app is only run from `.build/debug` there).
