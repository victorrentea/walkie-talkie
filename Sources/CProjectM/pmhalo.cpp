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
    "uniform sampler2D src;uniform vec2 point;uniform vec3 value;uniform float radius;uniform float aspect;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 d=uv-point;d.x*=aspect;float g=exp(-dot(d,d)/radius);"
    " frag=vec4(texture(src,uv).rgb+value*g,1.0);}\n";
const char* kAdvectFS = "#version 330 core\n"
    "uniform sampler2D vel;uniform sampler2D src;uniform vec2 texel;uniform float dt;uniform float dissipation;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 c=uv-dt*texture(vel,uv).xy*texel;"
    " frag=vec4(texture(src,c).rgb/(1.0+dissipation*dt),1.0);}\n";
// **The display of the pure fluid** (mode 3, Cursify's Fluid Cursor): the dye,
// lit as a surface whose height is its brightness (`SHADING: true`), keyed the
// way their `TRANSPARENT` canvas is — alpha = the brightest channel.
const char* kDisplayFS = "#version 330 core\n"
    "uniform sampler2D dye;uniform sampler2D bloom;uniform sampler2D sunrays;uniform float useBloom;uniform float useSunrays;"
    "uniform vec2 texel;uniform float shading;uniform float ceil_;uniform float opacity;in vec2 uv;out vec4 frag;\n"
    "void main(){vec3 c=min(texture(dye,uv).rgb,vec3(ceil_));"
    " if(shading>0.5){float dx=length(texture(dye,uv+vec2(texel.x,0)).rgb)-length(texture(dye,uv-vec2(texel.x,0)).rgb);"
    " float dy=length(texture(dye,uv+vec2(0,texel.y)).rgb)-length(texture(dye,uv-vec2(0,texel.y)).rgb);"
    " vec3 n=normalize(vec3(dx,dy,length(texel)));c*=clamp(n.z+0.7,0.7,1.0);}"
    // ink's bloom and sunrays (Pavel's full display shader)
    " vec3 b=vec3(0.0); if(useBloom>0.5) b=texture(bloom,uv).rgb;"
    // Two departures from Pavel, both because the paper here is the desktop and
    // not #0a0a0a (2026-09-23 captures): the sunrays factor reaches ~8.5 where
    // there is no ink, which on black lifts nothing and over a desktop lifts the
    // bloom's faint haze into a wash across the whole screen — so it is capped at
    // 1.5; and the dithering noise went, which through the gamma curve came out as
    // a striped grey veil at alpha ~0.05 everywhere.
    " if(useSunrays>0.5){float s=min(texture(sunrays,uv).r,1.5);c*=s;b*=s;}"
    " if(useBloom>0.5){b=max(b,vec3(0));b=max(1.055*pow(b,vec3(0.416666667))-0.055,vec3(0));c+=b;}"
    " c=min(c,vec3(1.0))*opacity;frag=vec4(c,max(c.r,max(c.g,c.b)));}\n";
const char* kPrefilterFS = "#version 330 core\n"
    "uniform sampler2D src;uniform vec3 curve;uniform float threshold;in vec2 uv;out vec4 frag;\n"
    "void main(){vec3 c=texture(src,uv).rgb;float br=max(c.r,max(c.g,c.b));"
    " float rq=clamp(br-curve.x,0.0,curve.y);rq=curve.z*rq*rq;"
    " c*=max(rq,br-threshold)/max(br,0.0001);frag=vec4(c,0.0);}\n";
// the bloom's four-tap blur (and, with `intensity`, its final pass); `texel` is the SOURCE's
const char* kBloomBlurFS = "#version 330 core\n"
    "uniform sampler2D src;uniform vec2 texel;uniform float intensity;in vec2 uv;out vec4 frag;\n"
    "void main(){vec4 s=texture(src,uv-vec2(texel.x,0))+texture(src,uv+vec2(texel.x,0))"
    "+texture(src,uv+vec2(0,texel.y))+texture(src,uv-vec2(0,texel.y));frag=s*0.25*intensity;}\n";
const char* kSunMaskFS = "#version 330 core\n"
    "uniform sampler2D src;in vec2 uv;out vec4 frag;\n"
    "void main(){vec4 c=texture(src,uv);float br=max(c.r,max(c.g,c.b));c.a=1.0-min(max(br*20.0,0.0),0.8);frag=c;}\n";
const char* kSunraysFS = "#version 330 core\n"
    "uniform sampler2D src;uniform float weight;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 coord=uv;vec2 dir=(uv-0.5)*(1.0/16.0*0.3);float decay=1.0;float col=texture(src,uv).a;"
    " for(int i=0;i<16;i++){coord-=dir;col+=texture(src,coord).a*decay*weight;decay*=0.95;}"
    " frag=vec4(col*0.7,0.0,0.0,1.0);}\n";
const char* kGaussFS = "#version 330 core\n"
    "uniform sampler2D src;uniform vec2 texel;in vec2 uv;out vec4 frag;\n"
    "void main(){vec2 o=texel*1.33333333;frag=texture(src,uv)*0.29411764+(texture(src,uv-o)+texture(src,uv+o))*0.35294117;}\n";
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
    GLuint tex = 0, fbo = 0; int w = 0, h = 0;
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
    // mode 3: the dye is a float field of its own, half the screen's pixels
    Field dye[2]; int dw = 0, dh = 0, dc = 0; GLuint displayProg = 0;
    // mode 5 (ink): the bloom pyramid and the sunrays
    Field bloom; std::vector<Field> bloomLevels; Field sun, sunTemp;
    GLuint prefilterProg = 0, bloomBlurProg = 0, sunMaskProg = 0, sunraysProg = 0, gaussProg = 0;
    float colorTimer = 1.f, cr = 0, cg = 0, cb = 0;
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
        for (Field& f : h->bloomLevels) { if (f.fbo) glDeleteFramebuffers(1, &f.fbo); if (f.tex) glDeleteTextures(1, &f.tex); }
        for (GLuint p : { h->prefilterProg, h->bloomBlurProg, h->sunMaskProg, h->sunraysProg, h->gaussProg })
            if (p) glDeleteProgram(p);
        for (GLuint p : { h->prog, h->dyeProg, h->displayProg, h->splatProg, h->advectProg, h->curlProg, h->vortProg, h->divProg, h->scaleProg, h->jacobiProg, h->gradProg })
            if (p) glDeleteProgram(p);
        for (Field* f : { &h->vel[0], &h->vel[1], &h->prs[0], &h->prs[1], &h->div, &h->curl, &h->dye[0], &h->dye[1], &h->bloom, &h->sun, &h->sunTemp }) {
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
    f.w = w; f.h = hgt;
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
    if (mode >= 2) {
        // mode 3 runs Cursify's grid: 128 cells on the short side (SIM_RESOLUTION)
        if (mode >= 3) { int s = mode == 4 ? 140 : mode == 5 ? 256 : 128; h->vw = w >= hgt ? (int)std::lround(s * (double)w / hgt) : s; h->vh = w >= hgt ? s : (int)std::lround(s * (double)hgt / w); }
        else { h->vw = std::max(32, w / 4); h->vh = std::max(32, hgt / 4); }
        for (Field* f : { &h->vel[0], &h->vel[1] }) if (!make_field(*f, h->vw, h->vh, GL_RG16F, GL_RG)) return bail("velocity field could not be made");
        for (Field* f : { &h->prs[0], &h->prs[1], &h->div, &h->curl }) if (!make_field(*f, h->vw, h->vh, GL_R16F, GL_RED)) return bail("pressure field could not be made");
        h->splatProg = link(kSplatFS, log); h->advectProg = link(kAdvectFS, log);
        h->curlProg = link(kCurlFS, log); h->vortProg = link(kVortFS, log);
        h->divProg = link(kDivFS, log); h->scaleProg = link(kScaleFS, log);
        h->jacobiProg = link(kJacobiFS, log); h->gradProg = link(kGradFS, log);
    }
    if (mode >= 3) {
        if (mode == 4 || mode == 5) { int d = mode == 4 ? 512 : 1024; h->dw = w >= hgt ? (int)std::lround(d * (double)w / hgt) : d; h->dh = w >= hgt ? d : (int)std::lround(d * (double)hgt / w); }
        else { h->dw = std::max(32, w / 2); h->dh = std::max(32, hgt / 2); }
        for (Field* f : { &h->dye[0], &h->dye[1] }) if (!make_field(*f, h->dw, h->dh, GL_RGBA16F, GL_RGBA)) return bail("dye field could not be made");
        h->displayProg = link(kDisplayFS, log);
    }
    if (mode == 5) {
        // at `res` cells on the short side, the other side by the aspect — ink's getResolution
        auto shortSide = [&](int r, int& fw, int& fh) { fw = w >= hgt ? (int)std::lround(r * (double)w / hgt) : r; fh = w >= hgt ? r : (int)std::lround(r * (double)hgt / w); };
        int bw, bh; shortSide(256, bw, bh);
        if (!make_field(h->bloom, bw, bh, GL_RGBA16F, GL_RGBA)) return bail("bloom field could not be made");
        for (int i = 0; i < 8; ++i) {
            int lw = bw >> (i + 1), lh = bh >> (i + 1);
            if (lw < 2 || lh < 2) break;
            Field f; if (!make_field(f, lw, lh, GL_RGBA16F, GL_RGBA)) return bail("bloom level could not be made");
            h->bloomLevels.push_back(f);
        }
        int sw, sh; shortSide(196, sw, sh);
        if (!make_field(h->sun, sw, sh, GL_RGBA16F, GL_RGBA) || !make_field(h->sunTemp, sw, sh, GL_RGBA16F, GL_RGBA)) return bail("sunrays field could not be made");
        h->prefilterProg = link(kPrefilterFS, log); h->bloomBlurProg = link(kBloomBlurFS, log);
        h->sunMaskProg = link(kSunMaskFS, log); h->sunraysProg = link(kSunraysFS, log); h->gaussProg = link(kGaussFS, log);
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

void splat(pmh* h, Field* f, int& cur, int w, int hgt, float x, float y, float vx, float vy, float vz, float radius) {
    glUseProgram(h->splatProg);
    bind2d(h->splatProg, "src", 0, f[cur].tex);
    glUniform2f(glGetUniformLocation(h->splatProg, "point"), x, y);
    glUniform3f(glGetUniformLocation(h->splatProg, "value"), vx, vy, vz);
    glUniform1f(glGetUniformLocation(h->splatProg, "radius"), radius);
    glUniform1f(glGetUniformLocation(h->splatProg, "aspect"), (float)h->ow / h->oh);
    glBindFramebuffer(GL_FRAMEBUFFER, f[cur ^ 1].fbo);
    glViewport(0, 0, w, hgt);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    cur ^= 1;
}

struct FluidParams { float curl, pressureKeep, velDissipation; int iterations = 20; };

// One step of the fluid, after whatever splats this frame put into it: curl,
// vorticity, pressure, projection, self-advection.
void step_fluid(pmh* h, float dt, FluidParams fp) {
    glDisable(GL_BLEND);
    // curl → vorticity confinement (the curls that make it smoke, not jelly)
    glUseProgram(h->curlProg); bind2d(h->curlProg, "vel", 0, h->vel[h->vc].tex);
    pass(h, h->curlProg, h->curl);
    glUseProgram(h->vortProg);
    bind2d(h->vortProg, "vel", 0, h->vel[h->vc].tex); bind2d(h->vortProg, "curl", 1, h->curl.tex);
    glUniform1f(glGetUniformLocation(h->vortProg, "strength"), fp.curl);
    glUniform1f(glGetUniformLocation(h->vortProg, "dt"), dt);
    pass(h, h->vortProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
    // divergence, pressure (warm-started at 0.8 of the last), gradient
    glUseProgram(h->divProg); bind2d(h->divProg, "vel", 0, h->vel[h->vc].tex);
    pass(h, h->divProg, h->div);
    glUseProgram(h->scaleProg); bind2d(h->scaleProg, "src", 0, h->prs[h->pc].tex);
    glUniform1f(glGetUniformLocation(h->scaleProg, "k"), fp.pressureKeep);
    pass(h, h->scaleProg, h->prs[h->pc ^ 1]); h->pc ^= 1;
    glUseProgram(h->jacobiProg);
    for (int i = 0; i < fp.iterations; ++i) {
        bind2d(h->jacobiProg, "pressure", 0, h->prs[h->pc].tex); bind2d(h->jacobiProg, "div", 1, h->div.tex);
        pass(h, h->jacobiProg, h->prs[h->pc ^ 1]); h->pc ^= 1;
    }
    glUseProgram(h->gradProg);
    bind2d(h->gradProg, "pressure", 0, h->prs[h->pc].tex); bind2d(h->gradProg, "vel", 1, h->vel[h->vc].tex);
    pass(h, h->gradProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
    // the velocity carries itself, and slowly dies
    glUseProgram(h->advectProg); bind2d(h->advectProg, "vel", 0, h->vel[h->vc].tex); bind2d(h->advectProg, "src", 1, h->vel[h->vc].tex);
    glUniform1f(glGetUniformLocation(h->advectProg, "dt"), dt);
    glUniform1f(glGetUniformLocation(h->advectProg, "dissipation"), fp.velDissipation);
    pass(h, h->advectProg, h->vel[h->vc ^ 1]); h->vc ^= 1;
}
}

void pmh_set_mask(pmh* h, bool fade, float rx, float ry, float floor_a, float gain, float fade_start, float hole, float peak, float core, float tail_top) {
    h->fade = fade; h->rx = rx; h->ry = ry; h->floorA = floor_a; h->gain = gain; h->fadeStart = fade_start;
    h->hole = hole; h->peak = peak; h->core = core; h->tailTop = tail_top;
}

namespace {
float hue_channel(float hh, float off) { float k = std::fmod(off + hh * 6.f, 6.f); return 1.f - std::max(0.f, std::min({ k, 4.f - k, 1.f })); }

// **Mode 3: Cursify's Fluid Cursor** (cursify.ui-layouts.com/components/fluid-cursor,
// Victor 2026-09-23: *"impl si asta"*). Pavel Dobryakov's fluid in its cursor form,
// with no MilkDrop preset: every frame the pointer's move splats velocity and dye
// into the field, the hue is redrawn ten times a second at 0.15 of full
// brightness, and the dye dies fast. Their constants, verbatim: SIM_RESOLUTION
// 128, DENSITY_DISSIPATION 3.5, VELOCITY_DISSIPATION 2, PRESSURE 0.1, 20
// iterations, CURL 3, SPLAT_RADIUS 0.2 (/100, ×aspect), SPLAT_FORCE 6000,
// COLOR_UPDATE_SPEED 10, SHADING on, TRANSPARENT.
struct Look {
    float curl, pressureKeep, velFade, dyeFade, force, radius; bool radiusByAspect;
    bool shading; float ceiling; float dtScale;   // solver dt = dtScale × frame time
    int palette;                                   // 0: a random hue 10×/s at `gain`; 1: violets per splat
    float gain;
    int iterations = 20;
    bool deltaByAspect = false;                    // Pavel's correctDeltaY: dy / aspect on a wide screen
    bool bloom = false, sunrays = false;
    float bloomIntensity = 0.3f, bloomThreshold = 0.6f, bloomKnee = 0.7f;
    float opacity = 1.f;                           // the whole layer, colour and alpha alike
};
// Cursify's constants (above). dt = the frame's time, as Pavel's loop does.
const Look kCursify = { 3.f, 0.1f, 2.f, 3.5f, 6000.f, 0.2f / 100.f, true, true, 1.f, 1.f, 0, 0.15f, 20, true };
// **Mode 4: liquid-cursor** (cravinadventure.github.io/liquid-cursor, Victor
// 2026-09-23: *"impl …"*), the same solver with its own tuning, from
// liquid-cursor.js v1.0.0 and the demo page's tag (`data-gain="0.15"`): curl 20,
// pressure kept at 0.8, motionFade 0.55, dyeFade 0.72 — the colour hangs in the
// air — force 2200, radius 0.24/100 with no aspect correction, five violets
// picked per splat, the dye ceilinged at 0.72, no shading. It steps a fixed
// 0.010 s per 60 Hz frame, i.e. 0.6 of real time: at 30 fps, 0.02.
// Their `drift` (ambient splats at random places) and the 16 opening splats are
// left out: on a desktop overlay they would be paint appearing away from the pointer.
const Look kLiquid = { 20.f, 0.8f, 0.55f, 0.72f, 2200.f, 0.24f / 100.f, false, false, 0.72f, 0.6f, 1, 0.15f };
// **Mode 5: ink** (mkmlman.github.io/ink, Victor 2026-09-23: *"poti si asta?"*) —
// Pavel's simulation whole, bloom and sunrays included, at the values its dial
// panel writes over `config` on load (dials.js `def`): radius 0.40, force 12000,
// brightness 3 (colour ×0.45), curl 4, velocity loss 0, ink persistence 4
// (DENSITY_DISSIPATION = 1 − 4·0.02 = 0.92), pressure loss 0.08 (PRESSURE =
// 1 − 2·0.08 = 0.84), 16 pressure steps, glow 0.30; sim 256, dye 1024, bloom
// 256 × 8 levels (threshold 0.6, knee 0.7), sunrays 196 weight 1. Their paper
// is opaque #0a0a0a; here it is the desktop, keyed to alpha.
// Then Victor, the same evening, on sight: *"mai mica dimens si luminozitate. si
// incearca sa o faci mai transparenta pe ink"* — the splat's radius halved (0.40 →
// 0.20), the colour 0.45 → 0.22 and the glow 0.30 → 0.15, the ink dying faster
// (0.92 → 2.0: at theirs, a pointer that keeps moving paints the whole screen
// within seconds, which on a paper is the point and on a desktop is a curtain),
// and the layer at 0.55 opacity.
const Look kInk = { 4.f, 0.84f, 0.f, 2.0f, 12000.f, 0.20f / 100.f, true, true, 10.f, 1.f, 0, 0.22f,
                    16, true, true, true, 0.15f, 0.6f, 0.7f, 0.55f };
const float kViolets[5][3] = { { 0.55f, 0.29f, 0.97f }, { 0.84f, 0.36f, 0.96f }, { 0.31f, 0.39f, 0.94f },
                               { 0.72f, 0.22f, 0.92f }, { 0.42f, 0.32f, 1.00f } };

void draw_into(const Field& f) {
    glBindFramebuffer(GL_FRAMEBUFFER, f.fbo);
    glViewport(0, 0, f.w, f.h);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

// Pavel's `applyBloom`: a thresholded copy of the dye, blurred down the pyramid,
// added back up it, and scaled by the intensity into `bloom`.
void apply_bloom(pmh* h, const Look& L) {
    if (h->bloomLevels.size() < 2) return;
    glDisable(GL_BLEND);
    glUseProgram(h->prefilterProg);
    float knee = L.bloomThreshold * L.bloomKnee + 0.0001f;
    glUniform3f(glGetUniformLocation(h->prefilterProg, "curve"), L.bloomThreshold - knee, knee * 2, 0.25f / knee);
    glUniform1f(glGetUniformLocation(h->prefilterProg, "threshold"), L.bloomThreshold);
    bind2d(h->prefilterProg, "src", 0, h->dye[h->dc].tex);
    draw_into(h->bloom);
    glUseProgram(h->bloomBlurProg);
    GLint uTexel = glGetUniformLocation(h->bloomBlurProg, "texel"), uInt = glGetUniformLocation(h->bloomBlurProg, "intensity");
    glUniform1f(uInt, 1.f);
    const Field* last = &h->bloom;
    for (Field& f : h->bloomLevels) {
        glUniform2f(uTexel, 1.f / last->w, 1.f / last->h);
        bind2d(h->bloomBlurProg, "src", 0, last->tex);
        draw_into(f); last = &f;
    }
    glEnable(GL_BLEND); glBlendEquation(GL_FUNC_ADD); glBlendFunc(GL_ONE, GL_ONE);
    for (int i = (int)h->bloomLevels.size() - 2; i >= 0; --i) {
        Field& base = h->bloomLevels[i];
        glUniform2f(uTexel, 1.f / last->w, 1.f / last->h);
        bind2d(h->bloomBlurProg, "src", 0, last->tex);
        draw_into(base); last = &base;
    }
    glDisable(GL_BLEND);
    glUniform2f(uTexel, 1.f / last->w, 1.f / last->h);
    glUniform1f(uInt, L.bloomIntensity);
    bind2d(h->bloomBlurProg, "src", 0, last->tex);
    draw_into(h->bloom);
}

// Pavel's `applySunrays` and its one blur: a mask where the dye is (dark) and is
// not (light), smeared radially from the middle of the screen, then blurred.
void apply_sunrays(pmh* h) {
    glDisable(GL_BLEND);
    Field& mask = h->dye[h->dc ^ 1];              // free until the next frame's advection
    glUseProgram(h->sunMaskProg);
    bind2d(h->sunMaskProg, "src", 0, h->dye[h->dc].tex);
    draw_into(mask);
    glUseProgram(h->sunraysProg);
    glUniform1f(glGetUniformLocation(h->sunraysProg, "weight"), 1.f);
    bind2d(h->sunraysProg, "src", 0, mask.tex);
    draw_into(h->sun);
    glUseProgram(h->gaussProg);
    GLint t = glGetUniformLocation(h->gaussProg, "texel");
    glUniform2f(t, 1.f / h->sun.w, 0.f); bind2d(h->gaussProg, "src", 0, h->sun.tex); draw_into(h->sunTemp);
    glUniform2f(t, 0.f, 1.f / h->sun.h); bind2d(h->gaussProg, "src", 0, h->sunTemp.tex); draw_into(h->sun);
}

IOSurfaceRef render_pure_fluid(pmh* h, const Look& L) {
    const float dt = 1.f / h->fps, sdt = dt * L.dtScale;
    Surface& s = h->surf[h->cur];
    glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST); glDisable(GL_SCISSOR_TEST);
    glBindVertexArray(h->vao);
    if (h->fresh) {
        glClearColor(0, 0, 0, 0);
        for (Field* f : { &h->vel[0], &h->vel[1], &h->prs[0], &h->prs[1], &h->dye[0], &h->dye[1] }) { glBindFramebuffer(GL_FRAMEBUFFER, f->fbo); glClear(GL_COLOR_BUFFER_BIT); }
        h->fresh = false;
    }
    h->colorTimer += dt * 10.f;
    if (L.palette == 1) {
        const float* v = kViolets[std::rand() % 5];
        h->cr = v[0] * L.gain; h->cg = v[1] * L.gain; h->cb = v[2] * L.gain;
    } else if (h->colorTimer >= 1.f) {
        h->colorTimer = std::fmod(h->colorTimer, 1.f);
        float hh = (float)std::rand() / RAND_MAX;
        h->cr = hue_channel(hh, 5) * L.gain; h->cg = hue_channel(hh, 3) * L.gain; h->cb = hue_channel(hh, 1) * L.gain;
    }
    float ax = h->sx, ay = h->sy;
    if (h->havePointer) {
        float a = h->lag > 0 ? 1.f - std::exp(-dt / h->lag) : 1.f;
        h->sx += (h->tx - h->sx) * a; h->sy += (h->ty - h->sy) * a;
        float dx = (h->sx - ax) / h->ow, dy = (h->sy - ay) / h->oh;
        if (std::fabs(dx) + std::fabs(dy) > 1e-5f) {
            float aspect = (float)h->ow / h->oh;
            float radius = L.radius * (L.radiusByAspect && aspect > 1 ? aspect : 1.f);
            float x = h->sx / h->ow, y = h->sy / h->oh;
            float ddy = L.deltaByAspect && aspect > 1 ? dy / aspect : dy;
            splat(h, h->vel, h->vc, h->vw, h->vh, x, y, dx * L.force, ddy * L.force, 0, radius);
            splat(h, h->dye, h->dc, h->dw, h->dh, x, y, h->cr, h->cg, h->cb, radius);
        }
    }
    step_fluid(h, sdt, { L.curl, L.pressureKeep, L.velFade, L.iterations });
    // the dye rides the velocity and dies at DENSITY_DISSIPATION
    glUseProgram(h->advectProg);
    bind2d(h->advectProg, "vel", 0, h->vel[h->vc].tex); bind2d(h->advectProg, "src", 1, h->dye[h->dc].tex);
    glUniform2f(glGetUniformLocation(h->advectProg, "texel"), 1.f / h->vw, 1.f / h->vh);
    glUniform1f(glGetUniformLocation(h->advectProg, "dt"), sdt);
    glUniform1f(glGetUniformLocation(h->advectProg, "dissipation"), L.dyeFade);
    glBindFramebuffer(GL_FRAMEBUFFER, h->dye[h->dc ^ 1].fbo);
    glViewport(0, 0, h->dw, h->dh);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    h->dc ^= 1;
    if (L.bloom) apply_bloom(h, L);
    if (L.sunrays) apply_sunrays(h);
    // shown
    glUseProgram(h->displayProg);
    bind2d(h->displayProg, "bloom", 1, h->bloom.tex);
    bind2d(h->displayProg, "sunrays", 2, h->sun.tex);
    glUniform1f(glGetUniformLocation(h->displayProg, "useBloom"), L.bloom ? 1.f : 0.f);
    glUniform1f(glGetUniformLocation(h->displayProg, "useSunrays"), L.sunrays ? 1.f : 0.f);
    bind2d(h->displayProg, "dye", 0, h->dye[h->dc].tex);
    glUniform2f(glGetUniformLocation(h->displayProg, "texel"), 1.f / h->dw, 1.f / h->dh);
    glUniform1f(glGetUniformLocation(h->displayProg, "shading"), L.shading ? 1.f : 0.f);
    glUniform1f(glGetUniformLocation(h->displayProg, "ceil_"), L.ceiling);
    glUniform1f(glGetUniformLocation(h->displayProg, "opacity"), L.opacity);
    glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
    glViewport(0, 0, h->ow, h->oh);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindVertexArray(0); glUseProgram(0);
    glActiveTexture(GL_TEXTURE2); glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE1); glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (h->finish) glFinish(); else glFlush();
    h->cur ^= 1;
    return s.ios;
}
}

IOSurfaceRef pmh_render(pmh* h) {
    CGLContextObj prev = CGLGetCurrentContext();
    CGLSetCurrentContext(h->ctx);
    double t0 = now_ms();
    if (h->mode >= 3) {
        IOSurfaceRef out = render_pure_fluid(h, h->mode == 5 ? kInk : h->mode == 4 ? kLiquid : kCursify);
        h->engineMs = 0; h->keyMs = now_ms() - t0;
        GLenum e = glGetError();
        CGLSetCurrentContext(prev);
        if (e != GL_NO_ERROR) { h->keyErrors++; return nullptr; }
        return out;
    }
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
        if (h->mode == 2 && h->havePointer) {
            // Stamp-to-stamp, the fluid is stirred where the square travelled
            // this frame, as fast as the pointer went (grid cells per second).
            glDisable(GL_BLEND);
            float fx = (h->sx - ax) / h->ow * h->vw / dt, fy = (h->sy - ay) / h->oh * h->vh / dt;
            float speed = std::sqrt(fx * fx + fy * fy), cap = 3000.f;
            if (speed > cap) { fx *= cap / speed; fy *= cap / speed; }
            float r = (float)h->px / h->ow * 0.35f;
            if (speed > 1.f) splat(h, h->vel, h->vc, h->vw, h->vh, h->sx / h->ow, h->sy / h->oh, fx, fy, 0, r * r);
            step_fluid(h, dt, { 30.f, 0.8f, 0.4f });
        }
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
