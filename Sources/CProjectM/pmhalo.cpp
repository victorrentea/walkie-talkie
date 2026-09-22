// See pmhalo.h. Lifted from the 2026-09-20 spike (`pm4.cpp`): a CGL 3.2 core
// context, projectM rendering into our own FBO (the vendored engine reads the
// target FBO from PROJECTM_TARGET_FBO — the two-line patch in
// vendor/projectm/target-fbo.patch — because 4.1.7 hard-binds FBO 0), then a
// keying pass (rgb → alpha = max(r,g,b), radial mask, gain) into an IOSurface a
// CALayer shows. Two surfaces alternate so the compositor never reads the one
// being written.
#define GL_SILENCE_DEPRECATION 1
#include "pmhalo.h"
#include <OpenGL/OpenGL.h>
#include <CoreGraphics/CoreGraphics.h>
#include <OpenGL/CGLIOSurface.h>
#include <OpenGL/gl3.h>
#include <projectM-4/projectM.h>
#include <projectM-4/core.h>
#include <projectM-4/audio.h>
#include <projectM-4/parameters.h>
#include <projectM-4/callbacks.h>
#include <projectM-4/render_opengl.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {
double now_ms() {
    using namespace std::chrono;
    return duration<double, std::milli>(steady_clock::now().time_since_epoch()).count();
}

const char* kVS = "#version 330 core\n"
    "const vec2 P[4]=vec2[4](vec2(-1,-1),vec2(1,-1),vec2(-1,1),vec2(1,1));out vec2 uv;"
    "void main(){vec2 p=P[gl_VertexID];uv=p*0.5+0.5;gl_Position=vec4(p,0,1);}\n";

// The page's mask (assets/milkdrop/halo.html), verbatim: stops 0→1, .28→.78,
// .5→.5, .75→.26, 1→floor, constant past 1; or, with fade_start > 0, full light
// out to that fraction of the radius and one smooth fall to the floor.
const char* kFS = "#version 330 core\n"
    "uniform sampler2D src;uniform float fade;uniform vec2 radii;uniform float floorA;uniform float gain;uniform float fadeStart;"
    "uniform float hole;uniform float peak;uniform float core;uniform float tailTop;"
    "in vec2 uv;out vec4 frag;\n"
    // `core` > 0: discul de dinainte isi pastreaza profilul intreg (plin pana la
    // `fadeStart` din el, apoi o cadere), dar se opreste la `tailTop` in loc de
    // zero — iar de acolo incolo se prelungeste stins pana la marginea ecranului.
    // Victor, 2026-09-22: *"centrul efectului ... sa ramana opac, ca pana acum.
    // Doar periferia ... sa o prelungesti cu transparenta mica pana la marginea
    // ecranului"*.
    "float mask(float d){"
    " if(core>0.0){"
    "  if(d>=core) return mix(tailTop,floorA,smoothstep(core,1.0,d));"
    "  float t=d/core;"
    "  return t<=fadeStart?1.0:mix(1.0,tailTop,smoothstep(fadeStart,1.0,t));}"
    " if(fadeStart>0.0) return d<=fadeStart?1.0:mix(1.0,floorA,smoothstep(fadeStart,1.0,d));"
    " if(d<=0.28) return mix(1.0,0.78,d/0.28);"
    " if(d<=0.50) return mix(0.78,0.50,(d-0.28)/0.22);"
    " if(d<=0.75) return mix(0.50,0.26,(d-0.50)/0.25);"
    " if(d<=1.00) return mix(0.26,floorA,(d-0.75)/0.25);"
    " return floorA;}\n"
    // `hole`: gaura din mijloc. Un preset ca Tunnel isi strange liniile spre centru
    // si acolo sta cursorul, deci se stinge dinauntru in afara, cu aceeasi panta
    // moale ca marginea, nu cu un cerc taiat.
    "float inner(float d){ return hole<=0.0 ? 1.0 : smoothstep(hole*0.45, hole, d); }\n"
    "void main(){"
    // GL's row 0 is the bottom; the IOSurface's row 0 is the top the layer shows.
    " vec4 c=texture(src,vec2(uv.x,1.0-uv.y));"
    " c.rgb=min(c.rgb*gain,1.0);"
    " float a=max(c.r,max(c.g,c.b));"
    " if(fade>0.5){float d=length((uv-0.5)/radii);float m=mask(d)*inner(d);a*=m;c.rgb*=m;}"
    " a*=peak;c.rgb*=peak;"
    " frag=vec4(c.rgb,a);}\n";

// ---- The trail and the fluid (2026-09-23) ---------------------------------
// Victor: *"un «tendrils2» care sa nu se translateze pe ecran imediat dupa mouse
// ci sa lase la mutarea mouseului urme in spate unde a fost"*. In these modes the
// output surface is the size of the SCREEN, not the square: each frame the
// previous surface is carried over, dimmed (and, for the fluid, advected along a
// velocity field the pointer stirs), and the keyed square is stamped over it at
// the pointer. What the square leaves behind is the trail. Everything here is in
// the surface's own convention: GL row 0 is the IOSurface's top row, so y is
// measured DOWN from the top — the same as the pointer handed in.
//
// The dye pass: the previous surface, sampled `dt·v` upstream (v = 0 for the
// plain trail), times `k`, minus `eps` so an 8-bit value cannot get stuck at the
// point where ×k rounds back to itself (below ~7/255 at k = 0.93).
const char* kDyeFS = "#version 330 core\n"
    "uniform sampler2DRect dye;uniform sampler2D vel;uniform vec2 size;uniform vec2 pxPerCell;uniform float dt;uniform float k;uniform float eps;uniform float useVel;"
    "out vec4 frag;\n"
    "void main(){vec2 p=gl_FragCoord.xy;"
    " if(useVel>0.5){vec2 v=texture(vel,p/size).xy;p-=dt*v*pxPerCell;}"
    " vec4 c=texture(dye,p)*k;"
    " frag=max(c-vec4(eps),vec4(0.0));}\n";

// The fluid itself — Jos Stam's stable fluids as Pavel Dobryakov's
// WebGL-Fluid-Simulation runs them (paveldogreat.github.io/WebGL-Fluid-Simulation,
// the effect four of the ten searches came back with). Velocity in grid cells
// per second, on a grid a quarter of the screen's pixels on each side.
const char* kSplatFS = "#version 330 core\n"
    "uniform sampler2D src;uniform vec2 point;uniform vec2 force;uniform float radius;uniform float aspect;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 d=uv-point;d.x*=aspect;float g=exp(-dot(d,d)/radius);"
    " frag=vec4(texture(src,uv).xy+force*g,0.0,1.0);}\n";
const char* kAdvectFS = "#version 330 core\n"
    "uniform sampler2D vel;uniform vec2 texel;uniform float dt;uniform float dissipation;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 c=uv-dt*texture(vel,uv).xy*texel;"
    " frag=vec4(texture(vel,c).xy/(1.0+dissipation*dt),0.0,1.0);}\n";
const char* kCurlFS = "#version 330 core\n"
    "uniform sampler2D vel;uniform vec2 texel;in vec2 uv;out vec4 frag;\n"
    "void main(){float L=texture(vel,uv-vec2(texel.x,0)).y;float R=texture(vel,uv+vec2(texel.x,0)).y;"
    " float T=texture(vel,uv+vec2(0,texel.y)).x;float B=texture(vel,uv-vec2(0,texel.y)).x;"
    " frag=vec4(0.5*(R-L-T+B),0,0,1);}\n";
const char* kVortFS = "#version 330 core\n"
    "uniform sampler2D vel;uniform sampler2D curl;uniform vec2 texel;uniform float strength;uniform float dt;in vec2 uv;out vec4 frag;\n"
    "void main(){float L=texture(curl,uv-vec2(texel.x,0)).x;float R=texture(curl,uv+vec2(texel.x,0)).x;"
    " float T=texture(curl,uv+vec2(0,texel.y)).x;float B=texture(curl,uv-vec2(0,texel.y)).x;float C=texture(curl,uv).x;"
    " vec2 f=0.5*vec2(abs(T)-abs(B),abs(R)-abs(L));f/=length(f)+0.0001;f*=strength*C;f.y*=-1.0;"
    " vec2 v=texture(vel,uv).xy+f*dt;frag=vec4(clamp(v,-1000.0,1000.0),0,1);}\n";
const char* kDivFS = "#version 330 core\n"
    "uniform sampler2D vel;uniform vec2 texel;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 C=texture(vel,uv).xy;"
    " float L=texture(vel,uv-vec2(texel.x,0)).x;float R=texture(vel,uv+vec2(texel.x,0)).x;"
    " float T=texture(vel,uv+vec2(0,texel.y)).y;float B=texture(vel,uv-vec2(0,texel.y)).y;"
    " if(uv.x-texel.x<0.0)L=-C.x; if(uv.x+texel.x>1.0)R=-C.x; if(uv.y+texel.y>1.0)T=-C.y; if(uv.y-texel.y<0.0)B=-C.y;"
    " frag=vec4(0.5*(R-L+T-B),0,0,1);}\n";
const char* kScaleFS = "#version 330 core\n"
    "uniform sampler2D src;uniform float k;in vec2 uv;out vec4 frag;\n"
    "void main(){frag=texture(src,uv)*k;}\n";
const char* kJacobiFS = "#version 330 core\n"
    "uniform sampler2D pressure;uniform sampler2D div;uniform vec2 texel;in vec2 uv;out vec4 frag;\n"
    "void main(){float L=texture(pressure,uv-vec2(texel.x,0)).x;float R=texture(pressure,uv+vec2(texel.x,0)).x;"
    " float T=texture(pressure,uv+vec2(0,texel.y)).x;float B=texture(pressure,uv-vec2(0,texel.y)).x;"
    " frag=vec4((L+R+B+T-texture(div,uv).x)*0.25,0,0,1);}\n";
const char* kGradFS = "#version 330 core\n"
    "uniform sampler2D pressure;uniform sampler2D vel;uniform vec2 texel;in vec2 uv;out vec4 frag;\n"
    "void main(){float L=texture(pressure,uv-vec2(texel.x,0)).x;float R=texture(pressure,uv+vec2(texel.x,0)).x;"
    " float T=texture(pressure,uv+vec2(0,texel.y)).x;float B=texture(pressure,uv-vec2(0,texel.y)).x;"
    " frag=vec4(texture(vel,uv).xy-vec2(R-L,T-B),0,1);}\n";

GLuint compile(GLenum type, const char* src, std::string& log) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok = 0; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char l[2048]; glGetShaderInfoLog(s, 2048, nullptr, l); log += l; }
    return s;
}

void set_err(char* err, int len, const std::string& s) {
    if (err && len > 0) { strncpy(err, s.c_str(), len - 1); err[len - 1] = 0; }
}

GLuint link(const char* fs, std::string& log) {
    GLuint v = compile(GL_VERTEX_SHADER, kVS, log), f = compile(GL_FRAGMENT_SHADER, fs, log);
    GLuint p = glCreateProgram(); glAttachShader(p, v); glAttachShader(p, f); glLinkProgram(p);
    glDeleteShader(v); glDeleteShader(f);
    GLint ok = 0; glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) { char l[2048]; glGetProgramInfoLog(p, 2048, nullptr, l); log += l; }
    return p;
}

/// A float texture the fluid keeps its fields in, with its framebuffer.
struct Field {
    GLuint tex = 0, fbo = 0;
};

struct Surface {
    IOSurfaceRef ios = nullptr;
    GLuint tex = 0, fbo = 0;
};
}

struct pmh {
    int px = 0;
    CGLPixelFormatObj pix = nullptr;
    CGLContextObj ctx = nullptr;
    GLuint tex = 0, rbo = 0, fbo = 0;        // the engine's target
    GLuint prog = 0, vao = 0;                 // the key pass
    GLint uFade, uRadii, uFloor, uGain, uStart, uSrc, uHole, uPeak, uCore, uTail;
    Surface surf[2]; int cur = 0;
    projectm_handle pm = nullptr;
    bool fade = false; float rx = 0.5f, ry = 0.5f, floorA = 0.1f, gain = 1.f, fadeStart = 0.f, hole = 0.f, peak = 1.f, core = 0.f, tailTop = 0.f;
    double engineMs = 0, keyMs = 0;
    unsigned engineErrors = 0, keyErrors = 0;
    bool finish = false;                      // WT_PM_FINISH=1: glFinish for honest timings
    std::string loadError;
    std::vector<float> resampled;
    std::vector<std::string> texDirs; std::vector<const char*> texDirPtrs;
    // The trail and the fluid — see `pmh_set_canvas`. `ow`×`oh` is the output
    // surface; the square `px` is stamped into it at the (smoothed) pointer.
    int ow = 0, oh = 0, mode = 0, fps = 30;
    float seconds = 0.6f, lag = 0.06f;
    bool havePointer = false, fresh = true;
    float tx = 0, ty = 0, sx = 0, sy = 0;
    GLuint dyeProg = 0;
    // fluid
    int vw = 0, vh = 0;
    Field vel[2], prs[2], div, curl; int vc = 0, pc = 0;
    GLuint splatProg = 0, advectProg = 0, curlProg = 0, vortProg = 0, divProg = 0, scaleProg = 0, jacobiProg = 0, gradProg = 0;
};

static void on_preset_failed(const char* filename, const char* message, void* user) {
    auto* h = static_cast<pmh*>(user);
    h->loadError = std::string(message ? message : "?");
}

// See the header. `PMH_TIME_SCALE` is defined by the build only when the vendored
// library was rebuilt with `walkie-audio-time.patch`; the stock engine has no
// `PM_TIME_SCALE` in it at all (`strings` on the .a finds it zero times).
extern "C" int pmh_honours_time_scale(void) {
#ifdef PMH_TIME_SCALE
    return 1;
#else
    return 0;
#endif
}

static bool make_surface(pmh* h, Surface& s, int sw, int sh) {
    // Rows aligned the way Metal wants an IOSurface it renders into — a 907 px
    // square (bpr 3628) aborted the process with `isMisalignedIOSurface`.
    int32_t w = sw, hh = sh, bpe = 4; uint32_t pf = 'BGRA';
    int32_t bpr = (int32_t)IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, (size_t)sw * 4);
    int32_t asz = (int32_t)IOSurfaceAlignProperty(kIOSurfaceAllocSize, (size_t)bpr * sh);
    const void* keys[] = { kIOSurfaceWidth, kIOSurfaceHeight, kIOSurfaceBytesPerElement, kIOSurfaceBytesPerRow, kIOSurfaceAllocSize, kIOSurfacePixelFormat };
    const void* vals[] = { CFNumberCreate(nullptr, kCFNumberSInt32Type, &w), CFNumberCreate(nullptr, kCFNumberSInt32Type, &hh),
                           CFNumberCreate(nullptr, kCFNumberSInt32Type, &bpe), CFNumberCreate(nullptr, kCFNumberSInt32Type, &bpr),
                           CFNumberCreate(nullptr, kCFNumberSInt32Type, &asz), CFNumberCreate(nullptr, kCFNumberSInt32Type, (int32_t*)&pf) };
    CFDictionaryRef d = CFDictionaryCreate(nullptr, keys, vals, 6, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (auto v : vals) CFRelease(v);
    s.ios = IOSurfaceCreate(d);
    CFRelease(d);
    if (!s.ios) return false;
    // **The surface is tagged sRGB.** Untagged, Core Animation shows it in the
    // display's own space — on a P3 panel every colour lands more saturated
    // than the same pixels in the web view, whose WebGL canvas is sRGB.
    // Measured on Mosaic (docs/projectm/captures/mosaic-match-2026-09-21/):
    // the engines' own readbacks agree on saturation (web 132, native 123
    // over the lit part) while on screen they did not (web ~115, native
    // ~150). `WT_PM_COLORSPACE=none` leaves the surface untagged.
    { const char* e = getenv("WT_PM_COLORSPACE");
      if (!(e && strcmp(e, "none") == 0)) {
          CGColorSpaceRef cs = CGColorSpaceCreateWithName(e && *e ? CFStringCreateWithCString(nullptr, e, kCFStringEncodingUTF8) : kCGColorSpaceSRGB);
          if (cs) { CFPropertyListRef pl = CGColorSpaceCopyPropertyList(cs);
                    if (pl) { IOSurfaceSetValue(s.ios, CFSTR("IOSurfaceColorSpace"), pl); CFRelease(pl); }
                    CGColorSpaceRelease(cs); } } }
    glGenTextures(1, &s.tex);
    glBindTexture(GL_TEXTURE_RECTANGLE, s.tex);
    if (CGLTexImageIOSurface2D(h->ctx, GL_TEXTURE_RECTANGLE, GL_RGBA, sw, sh, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, s.ios, 0) != kCGLNoError) return false;
    // Read back by the trail's dye pass, between pixel centres once the fluid
    // moves it — so filtered, and clamped (a rectangle texture cannot repeat).
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glGenFramebuffers(1, &s.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE, s.tex, 0);
    return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

pmh* pmh_create(int px, int fps, const char* const* texture_dirs, char* err, int err_len) {
    auto* h = new pmh();
    h->px = px; h->ow = px; h->oh = px; h->fps = fps > 0 ? fps : 30;
    h->finish = getenv("WT_PM_FINISH") != nullptr;
    CGLPixelFormatAttribute attrs[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8,
        kCGLPFADepthSize, (CGLPixelFormatAttribute)24,
        (CGLPixelFormatAttribute)0 };
    GLint npix = 0;
    if (CGLChoosePixelFormat(attrs, &h->pix, &npix) != kCGLNoError || !h->pix) { set_err(err, err_len, "CGLChoosePixelFormat failed"); pmh_destroy(h); return nullptr; }
    if (CGLCreateContext(h->pix, nullptr, &h->ctx) != kCGLNoError || !h->ctx) { set_err(err, err_len, "CGLCreateContext failed"); pmh_destroy(h); return nullptr; }
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);

    glGenTextures(1, &h->tex);
    glBindTexture(GL_TEXTURE_2D, h->tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, px, px, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glGenRenderbuffers(1, &h->rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, h->rbo);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, px, px);
    glGenFramebuffers(1, &h->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, h->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, h->tex, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, h->rbo);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { set_err(err, err_len, "engine FBO incomplete"); CGLSetCurrentContext(prev); pmh_destroy(h); return nullptr; }
    glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    for (auto& s : h->surf) {
        if (!make_surface(h, s, px, px)) { set_err(err, err_len, "IOSurface FBO could not be made"); CGLSetCurrentContext(prev); pmh_destroy(h); return nullptr; }
    }

    std::string log;
    GLuint v = compile(GL_VERTEX_SHADER, kVS, log), f = compile(GL_FRAGMENT_SHADER, kFS, log);
    if (!log.empty()) { set_err(err, err_len, "key shader: " + log); CGLSetCurrentContext(prev); pmh_destroy(h); return nullptr; }
    h->prog = glCreateProgram(); glAttachShader(h->prog, v); glAttachShader(h->prog, f); glLinkProgram(h->prog);
    glDeleteShader(v); glDeleteShader(f);
    glGenVertexArrays(1, &h->vao);
    h->uSrc = glGetUniformLocation(h->prog, "src");
    h->uFade = glGetUniformLocation(h->prog, "fade");
    h->uRadii = glGetUniformLocation(h->prog, "radii");
    h->uFloor = glGetUniformLocation(h->prog, "floorA");
    h->uHole = glGetUniformLocation(h->prog, "hole");
    h->uPeak = glGetUniformLocation(h->prog, "peak");
    h->uCore = glGetUniformLocation(h->prog, "core");
    h->uTail = glGetUniformLocation(h->prog, "tailTop");
    h->uGain = glGetUniformLocation(h->prog, "gain");
    h->uStart = glGetUniformLocation(h->prog, "fadeStart");

    // The vendored engine draws its final pass into whatever this names.
    { char b[32]; snprintf(b, sizeof b, "%u", h->fbo); setenv("PROJECTM_TARGET_FBO", b, 1); }
    h->pm = projectm_create();
    if (!h->pm) { set_err(err, err_len, "projectm_create failed"); CGLSetCurrentContext(prev); pmh_destroy(h); return nullptr; }
    projectm_set_window_size(h->pm, px, px);
    projectm_set_mesh_size(h->pm, 48, 36);
    projectm_set_fps(h->pm, fps > 0 ? fps : 30);
    projectm_set_aspect_correction(h->pm, true);
    projectm_set_beat_sensitivity(h->pm, 1.0f);
    projectm_set_preset_duration(h->pm, 1e7);
    projectm_set_soft_cut_duration(h->pm, 0.0);
    projectm_set_hard_cut_enabled(h->pm, false);
    projectm_set_preset_locked(h->pm, true);
    projectm_set_preset_switch_failed_event_callback(h->pm, on_preset_failed, h);
    if (texture_dirs) {
        for (const char* const* p = texture_dirs; *p; ++p) h->texDirs.emplace_back(*p);
        for (auto& s : h->texDirs) h->texDirPtrs.push_back(s.c_str());
        projectm_set_texture_search_paths(h->pm, h->texDirPtrs.data(), h->texDirPtrs.size());
    }
    CGLSetCurrentContext(prev);
    return h;
}

void pmh_destroy(pmh* h) {
    if (!h) return;
    CGLContextObj prev = CGLGetCurrentContext();
    if (h->ctx) CGLSetCurrentContext(h->ctx);
    if (h->pm) projectm_destroy(h->pm);
    if (h->ctx) {
        for (auto& s : h->surf) {
            if (s.fbo) glDeleteFramebuffers(1, &s.fbo);
            if (s.tex) glDeleteTextures(1, &s.tex);
            if (s.ios) CFRelease(s.ios);
        }
        for (GLuint p : { h->prog, h->dyeProg, h->splatProg, h->advectProg, h->curlProg, h->vortProg, h->divProg, h->scaleProg, h->jacobiProg, h->gradProg })
            if (p) glDeleteProgram(p);
        for (Field* f : { &h->vel[0], &h->vel[1], &h->prs[0], &h->prs[1], &h->div, &h->curl }) {
            if (f->fbo) glDeleteFramebuffers(1, &f->fbo);
            if (f->tex) glDeleteTextures(1, &f->tex);
        }
        if (h->vao) glDeleteVertexArrays(1, &h->vao);
        if (h->fbo) glDeleteFramebuffers(1, &h->fbo);
        if (h->rbo) glDeleteRenderbuffers(1, &h->rbo);
        if (h->tex) glDeleteTextures(1, &h->tex);
        CGLSetCurrentContext(prev == h->ctx ? nullptr : prev);
        CGLDestroyContext(h->ctx);
    }
    if (h->pix) CGLDestroyPixelFormat(h->pix);
    delete h;
}

int pmh_load_preset(pmh* h, const char* milk, char* err, int err_len) {
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);
    h->loadError.clear();
    projectm_load_preset_data(h->pm, milk, false);
    CGLSetCurrentContext(prev);
    if (!h->loadError.empty()) { set_err(err, err_len, h->loadError); return 1; }
    return 0;
}

void pmh_add_pcm(pmh* h, const float* samples, unsigned count, int rate) {
    if (!count) return;
    if (rate <= 0 || rate == 44100) { projectm_pcm_add_float(h->pm, samples, count, PROJECTM_MONO); return; }
    // Linear resampling to 44.1 kHz: the engine's spectrum bands assume it.
    double step = (double)rate / 44100.0;
    unsigned out = (unsigned)(count / step);
    h->resampled.resize(out);
    for (unsigned i = 0; i < out; ++i) {
        double pos = i * step; unsigned k = (unsigned)pos; double f = pos - k;
        float a = samples[k], b = samples[k + 1 < count ? k + 1 : k];
        h->resampled[i] = (float)(a + (b - a) * f);
    }
    projectm_pcm_add_float(h->pm, h->resampled.data(), out, PROJECTM_MONO);
}


static bool make_field(Field& f, int w, int hgt, GLenum internal, GLenum format) {
    glGenTextures(1, &f.tex);
    glBindTexture(GL_TEXTURE_2D, f.tex);
    glTexImage2D(GL_TEXTURE_2D, 0, internal, w, hgt, 0, format, GL_HALF_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glGenFramebuffers(1, &f.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, f.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, f.tex, 0);
    bool ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT);
    return ok;
}

int pmh_set_canvas(pmh* h, int w, int hgt, int mode, float seconds, float lag, char* err, int err_len) {
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);
    auto bail = [&](const std::string& why) { set_err(err, err_len, why); CGLSetCurrentContext(prev); return 1; };
    for (auto& s : h->surf) {
        if (s.fbo) glDeleteFramebuffers(1, &s.fbo);
        if (s.tex) glDeleteTextures(1, &s.tex);
        if (s.ios) CFRelease(s.ios);
        s = Surface();
        if (!make_surface(h, s, w, hgt)) return bail("screen-sized IOSurface FBO could not be made");
    }
    h->ow = w; h->oh = hgt; h->mode = mode; h->seconds = seconds; h->lag = lag; h->fresh = true;
    std::string log;
    if (!h->dyeProg) h->dyeProg = link(kDyeFS, log);
    if (mode == 2) {
        h->vw = std::max(32, w / 4); h->vh = std::max(32, hgt / 4);
        for (Field* f : { &h->vel[0], &h->vel[1] }) if (!make_field(*f, h->vw, h->vh, GL_RG16F, GL_RG)) return bail("velocity field could not be made");
        for (Field* f : { &h->prs[0], &h->prs[1], &h->div, &h->curl }) if (!make_field(*f, h->vw, h->vh, GL_R16F, GL_RED)) return bail("pressure field could not be made");
        h->splatProg = link(kSplatFS, log); h->advectProg = link(kAdvectFS, log);
        h->curlProg = link(kCurlFS, log); h->vortProg = link(kVortFS, log);
        h->divProg = link(kDivFS, log); h->scaleProg = link(kScaleFS, log);
        h->jacobiProg = link(kJacobiFS, log); h->gradProg = link(kGradFS, log);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (!log.empty()) return bail("trail shaders: " + log);
    CGLSetCurrentContext(prev);
    return 0;
}

void pmh_set_pointer(pmh* h, float x, float y) {
    h->tx = x; h->ty = y;
    if (!h->havePointer) { h->sx = x; h->sy = y; h->havePointer = true; }
}

void pmh_reset_trail(pmh* h) { h->fresh = true; h->havePointer = false; }

void pmh_output_size(pmh* h, int* w, int* hgt) { *w = h->ow; *hgt = h->oh; }

namespace {
// One pass of the fluid: `prog` over the whole grid into `dst`.
void pass(pmh* h, GLuint prog, Field& dst) {
    glBindFramebuffer(GL_FRAMEBUFFER, dst.fbo);
    glViewport(0, 0, h->vw, h->vh);
    glUseProgram(prog);
    GLint t = glGetUniformLocation(prog, "texel");
    if (t >= 0) glUniform2f(t, 1.f / h->vw, 1.f / h->vh);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}
void bind2d(GLuint prog, const char* name, int unit, GLuint tex) {
    glActiveTexture(GL_TEXTURE0 + unit); glBindTexture(GL_TEXTURE_2D, tex);
    glUniform1i(glGetUniformLocation(prog, name), unit);
}

// Stamp-to-stamp, the fluid is stirred where the square travelled this frame:
// a velocity splat along the way, as fast as the pointer went.
void step_fluid(pmh* h, float dt, float ax, float ay, float bx, float by) {
    glDisable(GL_BLEND);
    // pointer displacement → grid cells per second
    float fx = (bx - ax) / h->ow * h->vw / dt, fy = (by - ay) / h->oh * h->vh / dt;
    float speed = std::sqrt(fx * fx + fy * fy);
    if (speed > 1.f) {
        float cap = 3000.f;
        if (speed > cap) { fx *= cap / speed; fy *= cap / speed; }
        // radius: the square's own size, so the swirl is as wide as the halo
        float r = (float)h->px / h->ow * 0.35f;
        glUseProgram(h->splatProg);
        bind2d(h->splatProg, "src", 0, h->vel[h->vc].tex);
        glUniform2f(glGetUniformLocation(h->splatProg, "point"), bx / h->ow, by / h->oh);
        glUniform2f(glGetUniformLocation(h->splatProg, "force"), fx, fy);
        glUniform1f(glGetUniformLocation(h->splatProg, "radius"), r * r);
        glUniform1f(glGetUniformLocation(h->splatProg, "aspect"), (float)h->ow / h->oh);
        pass(h, h->splatProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
    }
    // curl → vorticity confinement (the curls that make it smoke, not jelly)
    glUseProgram(h->curlProg); bind2d(h->curlProg, "vel", 0, h->vel[h->vc].tex);
    pass(h, h->curlProg, h->curl);
    glUseProgram(h->vortProg);
    bind2d(h->vortProg, "vel", 0, h->vel[h->vc].tex); bind2d(h->vortProg, "curl", 1, h->curl.tex);
    glUniform1f(glGetUniformLocation(h->vortProg, "strength"), 30.f);
    glUniform1f(glGetUniformLocation(h->vortProg, "dt"), dt);
    pass(h, h->vortProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
    // divergence, pressure (warm-started at 0.8 of the last), gradient
    glUseProgram(h->divProg); bind2d(h->divProg, "vel", 0, h->vel[h->vc].tex);
    pass(h, h->divProg, h->div);
    glUseProgram(h->scaleProg); bind2d(h->scaleProg, "src", 0, h->prs[h->pc].tex);
    glUniform1f(glGetUniformLocation(h->scaleProg, "k"), 0.8f);
    pass(h, h->scaleProg, h->prs[h->pc ^ 1]); h->pc ^= 1;
    glUseProgram(h->jacobiProg);
    for (int i = 0; i < 20; ++i) {
        bind2d(h->jacobiProg, "pressure", 0, h->prs[h->pc].tex); bind2d(h->jacobiProg, "div", 1, h->div.tex);
        pass(h, h->jacobiProg, h->prs[h->pc ^ 1]); h->pc ^= 1;
    }
    glUseProgram(h->gradProg);
    bind2d(h->gradProg, "pressure", 0, h->prs[h->pc].tex); bind2d(h->gradProg, "vel", 1, h->vel[h->vc].tex);
    pass(h, h->gradProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
    // the velocity carries itself, and slowly dies
    glUseProgram(h->advectProg); bind2d(h->advectProg, "vel", 0, h->vel[h->vc].tex);
    glUniform1f(glGetUniformLocation(h->advectProg, "dt"), dt);
    glUniform1f(glGetUniformLocation(h->advectProg, "dissipation"), 0.4f);
    pass(h, h->advectProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
}
}

void pmh_set_mask(pmh* h, bool fade, float rx, float ry, float floor_a, float gain, float fade_start, float hole, float peak, float core, float tail_top) {
    h->fade = fade; h->rx = rx; h->ry = ry; h->floorA = floor_a; h->gain = gain; h->fadeStart = fade_start;
    h->hole = hole; h->peak = peak; h->core = core; h->tailTop = tail_top;
}

IOSurfaceRef pmh_render(pmh* h) {
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);
    double t0 = now_ms();
    glBindFramebuffer(GL_FRAMEBUFFER, h->fbo);
    glViewport(0, 0, h->px, h->px);
    projectm_opengl_render_frame(h->pm);
    if (h->finish) glFinish();
    double t1 = now_ms();
    h->engineMs = t1 - t0;
    // The engine leaves GL errors behind on this driver (an unloadable texture
    // unit it warns about itself); they are its, not the key pass's. Counted, drained.
    while (glGetError() != GL_NO_ERROR) h->engineErrors++;

    Surface& s = h->surf[h->cur];
    glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST); glDisable(GL_SCISSOR_TEST);
    glBindVertexArray(h->vao);
    // Where the square goes this frame, and where it went the last: the key pass
    // is drawn once per stamp, `peak` scaled for the in-between ones.
    struct Stamp { float x, y, peak; };
    std::vector<Stamp> stamps;
    if (h->mode == 0) {
        glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
        glViewport(0, 0, h->px, h->px);
        stamps.push_back({ 0, 0, 1 });
    } else {
        const float dt = 1.f / h->fps;
        // per frame, the share of the light that survives: e^(−dt/τ)
        const float k = std::exp(-dt / std::max(0.05f, h->seconds));
        Surface& last = h->surf[h->cur ^ 1];
        if (h->fresh) {
            for (auto& q : h->surf) { glBindFramebuffer(GL_FRAMEBUFFER, q.fbo); glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT); }
            if (h->mode == 2) for (Field* f : { &h->vel[0], &h->vel[1], &h->prs[0], &h->prs[1] }) { glBindFramebuffer(GL_FRAMEBUFFER, f->fbo); glClear(GL_COLOR_BUFFER_BIT); }
            h->fresh = false;
        }
        // The square chases the pointer instead of sitting on it: a lag of
        // `lag` seconds, so a flick is a glide and never a jump.
        float ax = h->sx, ay = h->sy;
        if (h->havePointer) {
            float a = h->lag > 0 ? 1.f - std::exp(-dt / h->lag) : 1.f;
            h->sx += (h->tx - h->sx) * a; h->sy += (h->ty - h->sy) * a;
        }
        if (h->mode == 2 && h->havePointer) step_fluid(h, dt, ax, ay, h->sx, h->sy);
        glDisable(GL_BLEND);
        glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
        glViewport(0, 0, h->ow, h->oh);
        glUseProgram(h->dyeProg);
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_RECTANGLE, last.tex);
        glUniform1i(glGetUniformLocation(h->dyeProg, "dye"), 0);
        glActiveTexture(GL_TEXTURE1); glBindTexture(GL_TEXTURE_2D, h->mode == 2 ? h->vel[h->vc].tex : 0);
        glUniform1i(glGetUniformLocation(h->dyeProg, "vel"), 1);
        glUniform2f(glGetUniformLocation(h->dyeProg, "size"), (float)h->ow, (float)h->oh);
        glUniform2f(glGetUniformLocation(h->dyeProg, "pxPerCell"), h->vw ? (float)h->ow / h->vw : 1.f, h->vh ? (float)h->oh / h->vh : 1.f);
        glUniform1f(glGetUniformLocation(h->dyeProg, "dt"), dt);
        glUniform1f(glGetUniformLocation(h->dyeProg, "k"), k);
        glUniform1f(glGetUniformLocation(h->dyeProg, "eps"), 1.5f / 255.f);
        glUniform1f(glGetUniformLocation(h->dyeProg, "useVel"), h->mode == 2 ? 1.f : 0.f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glActiveTexture(GL_TEXTURE1); glBindTexture(GL_TEXTURE_2D, 0);
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_RECTANGLE, 0);
        if (h->havePointer) {
            // In-between stamps every ~6 % of the square, so a fast move is a
            // smear and not a row of copies; each as dim as it would have become
            // had it been drawn at its own moment of the frame.
            float dx = h->sx - ax, dy = h->sy - ay, dist = std::sqrt(dx * dx + dy * dy);
            int n = std::min(16, std::max(1, (int)std::ceil(dist / std::max(1.f, h->px * 0.06f))));
            for (int i = 1; i <= n; ++i) {
                float t = (float)i / n;
                stamps.push_back({ ax + dx * t, ay + dy * t, i == n ? 1.f : std::pow(k, 1.f - t) });
            }
        }
        // **MAX, not "over"**: laid over one another, thirty stamps a second
        // saturate into an opaque blob within a few frames (the first captures,
        // 2026-09-23), and a pointer standing still would do the same on one
        // spot. Per-channel max keeps the head exactly as bright as the preset
        // and lets the trail be only its fading past, never a sum of it.
        // The fluid is the exception, and keeps "over": smoke is exactly the
        // build-up the trail must not have, and advected at MAX it dies within a
        // stamp's width of the head.
        glEnable(GL_BLEND);
        glBlendEquation(h->mode == 2 ? GL_FUNC_ADD : GL_MAX);
        if (h->mode == 2) glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA); else glBlendFunc(GL_ONE, GL_ONE);
    }
    glUseProgram(h->prog);
    glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, h->tex);
    glUniform1i(h->uSrc, 0);
    glUniform1f(h->uFade, h->fade ? 1.f : 0.f);
    glUniform2f(h->uRadii, h->rx, h->ry);
    glUniform1f(h->uFloor, h->floorA);
    glUniform1f(h->uHole, h->hole);
    glUniform1f(h->uCore, h->core);
    glUniform1f(h->uTail, h->tailTop);
    glUniform1f(h->uGain, h->gain);
    glUniform1f(h->uStart, h->fadeStart);
    for (const Stamp& st : stamps) {
        glUniform1f(h->uPeak, h->peak * st.peak);
        if (h->mode != 0) glViewport((GLint)std::lround(st.x - h->px / 2.0), (GLint)std::lround(st.y - h->px / 2.0), h->px, h->px);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    glDisable(GL_BLEND); glBlendEquation(GL_FUNC_ADD);
    glBindVertexArray(0); glUseProgram(0); glBindTexture(GL_TEXTURE_2D, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (h->finish) glFinish(); else glFlush();
    h->keyMs = now_ms() - t1;
    GLenum e = glGetError();
    CGLSetCurrentContext(prev);
    if (e != GL_NO_ERROR) { h->keyErrors++; return nullptr; }
    h->cur ^= 1;
    return s.ios;
}

// Debug: mean alpha of each surface as GL reads it and as the CPU reads its memory.
void pmh_debug_alpha(pmh* h) {
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);
    glFinish();
    std::vector<unsigned char> buf((size_t)h->px * h->px * 4);
    for (int i = 0; i < 2; ++i) {
        Surface& s = h->surf[i];
        glBindFramebuffer(GL_READ_FRAMEBUFFER, s.fbo); glReadBuffer(GL_COLOR_ATTACHMENT0);
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadPixels(0, 0, h->px, h->px, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
        double ga = 0; for (size_t q = 3; q < buf.size(); q += 4) ga += buf[q];
        IOSurfaceLock(s.ios, kIOSurfaceLockReadOnly, nullptr);
        const unsigned char* m = (const unsigned char*)IOSurfaceGetBaseAddress(s.ios);
        size_t bpr = IOSurfaceGetBytesPerRow(s.ios);
        double ma = 0; for (int y = 0; y < h->px; ++y) for (int x = 0; x < h->px; ++x) ma += m[y * bpr + x * 4 + 3];
        IOSurfaceUnlock(s.ios, kIOSurfaceLockReadOnly, nullptr);
        fprintf(stderr, "[pmh] surface %d (cur=%d): gl mean alpha %.1f, memory mean alpha %.1f\n", i, h->cur, ga / (h->px * (double)h->px), ma / (h->px * (double)h->px));
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CGLSetCurrentContext(prev);
}

double pmh_last_engine_ms(pmh* h) { return h->engineMs; }
double pmh_last_key_ms(pmh* h) { return h->keyMs; }
unsigned pmh_engine_gl_errors(pmh* h) { return h->engineErrors; }

int pmh_read_pixels(pmh* h, unsigned char* out) {
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);
    Surface& s = h->surf[h->cur ^ 1];
    glBindFramebuffer(GL_READ_FRAMEBUFFER, s.fbo);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, h->ow, h->oh, GL_RGBA, GL_UNSIGNED_BYTE, out);
    GLenum e = glGetError();
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CGLSetCurrentContext(prev);
    return e == GL_NO_ERROR ? 0 : 1;
}
