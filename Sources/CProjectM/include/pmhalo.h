// The native MilkDrop halo's GL glue: projectM 4 rendered off screen in a CGL
// context, keyed to alpha, and handed to Core Animation as an IOSurface.
// Everything OpenGL lives here, in C++, so `ProjectMHalo.swift` never touches a
// GL call. See `ProjectMHalo.swift` for the contract and `vendor/projectm/` for
// the engine build.
#pragma once
#include <IOSurface/IOSurface.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pmh pmh;

/// A renderer drawing `px` × `px` pixels. `texture_dirs` is a NULL-terminated
/// list of folders projectM searches for a preset's textures. Returns NULL and
/// writes why into `err` (if given) when the GL context or projectM cannot be had.
pmh* pmh_create(int px, int fps, const char* const* texture_dirs, char* err, int err_len);
void pmh_destroy(pmh* h);

/// Load a preset from its `.milk` text. Returns 0 on success; on failure the
/// engine keeps its idle preset and `err` says what projectM said.
int pmh_load_preset(pmh* h, const char* milk, char* err, int err_len);

/// Push microphone samples (mono float, at `rate` Hz — resampled to 44.1 kHz for
/// the engine's beat detection, which assumes it).
void pmh_add_pcm(pmh* h, const float* samples, unsigned count, int rate);

/// The keying pass's mask (the page's four-stop mask, or one fall from
/// `fade_start`), all in fractions of the square's side: `rx`/`ry` are the fade
/// radii, `floor_a` what remains past them, `gain` a multiplier before keying.
void pmh_set_mask(pmh* h, bool fade, float rx, float ry, float floor_a, float gain, float fade_start, float hole, float peak, float core, float tail_top);

/// The picture turned inside out about its centre: a pixel at `d` mask radii
/// shows the engine's pixel at `invert` − `d`. 0 = off.
void pmh_set_invert(pmh* h, float invert);

/// **The trail** (2026-09-23): the output surface becomes `w` × `h` — the screen,
/// in pixels — and each frame carries the last one over, dimmed with a time
/// constant of `seconds`, before the keyed square is stamped at the pointer. The
/// square chases the pointer with a lag of `lag` seconds. `mode` 1 = the plain
/// trail, 2 = the same trail advected by a fluid the pointer stirs; 0 = the
/// square as before (the surface is the square). Returns 0 on success.
int pmh_set_canvas(pmh* h, int w, int h_, int mode, float seconds, float lag, char* err, int err_len);
/// The pointer, in output pixels, y down from the top. Trail modes only.
void pmh_set_pointer(pmh* h, float x, float y);
/// Forget the trail: the next frame starts on a clear surface at the pointer.
void pmh_reset_trail(pmh* h);
/// The surface's size in pixels — `px` × `px` unless a trail made it the screen.
void pmh_output_size(pmh* h, int* w, int* h_);

/// **The pure fluid's knobs** (modes 3–5), for the on-screen sliders: read the
/// mode's value, or set it live — the next frame uses it. Radius is in Pavel's
/// units (SPLAT_RADIUS / 100), gain the dye's colour multiplier, fade the dye's
/// dissipation per second, curl the vorticity, force the splat force, opacity the
/// whole layer's.
enum { PMH_FLUID_RADIUS = 0, PMH_FLUID_GAIN, PMH_FLUID_FADE, PMH_FLUID_CURL, PMH_FLUID_FORCE, PMH_FLUID_OPACITY };
void pmh_set_fluid_param(pmh* h, int which, float value);
float pmh_fluid_param(pmh* h, int which);

/// Render one frame and key it. Returns the IOSurface carrying it (owned by the
/// renderer, valid until the frame after next), or NULL on a GL failure.
IOSurfaceRef pmh_render(pmh* h);

/// **Does this build of the engine read `PM_TIME_SCALE`?** 1 when the library was
/// rebuilt with `walkie-audio-time.patch` (a preset's own clock, the native twin
/// of butterchurn's `render({elapsedTime})`), 0 for the stock vendored one. Swift
/// asks rather than assumes, because the two `.a` files are otherwise
/// indistinguishable from up there and a `speed` that quietly does nothing is
/// worse than one that is refused out loud.
int pmh_honours_time_scale(void);

/// The GPU-inclusive time of the last `pmh_render`, in ms (engine part and key part).
double pmh_last_engine_ms(pmh* h);
double pmh_last_key_ms(pmh* h);
/// GL errors the engine itself left behind so far (drained, never fatal).
unsigned pmh_engine_gl_errors(pmh* h);
void pmh_debug_alpha(pmh* h);

/// Read the last rendered surface back as RGBA (top row first), for tests.
/// `out` must hold w*h*4 bytes of `pmh_output_size`. Returns 0 on success.
int pmh_read_pixels(pmh* h, unsigned char* out);

#ifdef __cplusplus
}
#endif
