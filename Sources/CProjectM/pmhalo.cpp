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
#include <OpenGL/CGLIOSurface.h>
#include <OpenGL/gl3.h>
#include <projectM-4/projectM.h>
#include <projectM-4/core.h>
#include <projectM-4/audio.h>
#include <projectM-4/parameters.h>
#include <projectM-4/callbacks.h>
#include <projectM-4/render_opengl.h>
#include <chrono>
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
    "in vec2 uv;out vec4 frag;\n"
    "float mask(float d){"
    " if(fadeStart>0.0) return d<=fadeStart?1.0:mix(1.0,floorA,smoothstep(fadeStart,1.0,d));"
    " if(d<=0.28) return mix(1.0,0.78,d/0.28);"
    " if(d<=0.50) return mix(0.78,0.50,(d-0.28)/0.22);"
    " if(d<=0.75) return mix(0.50,0.26,(d-0.50)/0.25);"
    " if(d<=1.00) return mix(0.26,floorA,(d-0.75)/0.25);"
    " return floorA;}\n"
    "void main(){"
    // GL's row 0 is the bottom; the IOSurface's row 0 is the top the layer shows.
    " vec4 c=texture(src,vec2(uv.x,1.0-uv.y));"
    " c.rgb=min(c.rgb*gain,1.0);"
    " float a=max(c.r,max(c.g,c.b));"
    " if(fade>0.5){float m=mask(length((uv-0.5)/radii));a*=m;c.rgb*=m;}"
    " frag=vec4(c.rgb,a);}\n";

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
    GLint uFade, uRadii, uFloor, uGain, uStart, uSrc;
    Surface surf[2]; int cur = 0;
    projectm_handle pm = nullptr;
    bool fade = false; float rx = 0.5f, ry = 0.5f, floorA = 0.1f, gain = 1.f, fadeStart = 0.f;
    double engineMs = 0, keyMs = 0;
    unsigned engineErrors = 0, keyErrors = 0;
    bool finish = false;                      // WT_PM_FINISH=1: glFinish for honest timings
    std::string loadError;
    std::vector<float> resampled;
    std::vector<std::string> texDirs; std::vector<const char*> texDirPtrs;
};

static void on_preset_failed(const char* filename, const char* message, void* user) {
    auto* h = static_cast<pmh*>(user);
    h->loadError = std::string(message ? message : "?");
}

static bool make_surface(pmh* h, Surface& s) {
    // Rows aligned the way Metal wants an IOSurface it renders into — a 907 px
    // square (bpr 3628) aborted the process with `isMisalignedIOSurface`.
    int32_t w = h->px, bpe = 4; uint32_t pf = 'BGRA';
    int32_t bpr = (int32_t)IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, (size_t)h->px * 4);
    int32_t asz = (int32_t)IOSurfaceAlignProperty(kIOSurfaceAllocSize, (size_t)bpr * h->px);
    const void* keys[] = { kIOSurfaceWidth, kIOSurfaceHeight, kIOSurfaceBytesPerElement, kIOSurfaceBytesPerRow, kIOSurfaceAllocSize, kIOSurfacePixelFormat };
    const void* vals[] = { CFNumberCreate(nullptr, kCFNumberSInt32Type, &w), CFNumberCreate(nullptr, kCFNumberSInt32Type, &w),
                           CFNumberCreate(nullptr, kCFNumberSInt32Type, &bpe), CFNumberCreate(nullptr, kCFNumberSInt32Type, &bpr),
                           CFNumberCreate(nullptr, kCFNumberSInt32Type, &asz), CFNumberCreate(nullptr, kCFNumberSInt32Type, (int32_t*)&pf) };
    CFDictionaryRef d = CFDictionaryCreate(nullptr, keys, vals, 6, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (auto v : vals) CFRelease(v);
    s.ios = IOSurfaceCreate(d);
    CFRelease(d);
    if (!s.ios) return false;
    glGenTextures(1, &s.tex);
    glBindTexture(GL_TEXTURE_RECTANGLE, s.tex);
    if (CGLTexImageIOSurface2D(h->ctx, GL_TEXTURE_RECTANGLE, GL_RGBA, h->px, h->px, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, s.ios, 0) != kCGLNoError) return false;
    glGenFramebuffers(1, &s.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE, s.tex, 0);
    return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

pmh* pmh_create(int px, int fps, const char* const* texture_dirs, char* err, int err_len) {
    auto* h = new pmh();
    h->px = px;
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
        if (!make_surface(h, s)) { set_err(err, err_len, "IOSurface FBO could not be made"); CGLSetCurrentContext(prev); pmh_destroy(h); return nullptr; }
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
        if (h->prog) glDeleteProgram(h->prog);
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

void pmh_set_mask(pmh* h, bool fade, float rx, float ry, float floor_a, float gain, float fade_start) {
    h->fade = fade; h->rx = rx; h->ry = ry; h->floorA = floor_a; h->gain = gain; h->fadeStart = fade_start;
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
    glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
    glViewport(0, 0, h->px, h->px);
    glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST); glDisable(GL_SCISSOR_TEST);
    glUseProgram(h->prog); glBindVertexArray(h->vao);
    glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, h->tex);
    glUniform1i(h->uSrc, 0);
    glUniform1f(h->uFade, h->fade ? 1.f : 0.f);
    glUniform2f(h->uRadii, h->rx, h->ry);
    glUniform1f(h->uFloor, h->floorA);
    glUniform1f(h->uGain, h->gain);
    glUniform1f(h->uStart, h->fadeStart);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
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
    glReadPixels(0, 0, h->px, h->px, GL_RGBA, GL_UNSIGNED_BYTE, out);
    GLenum e = glGetError();
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CGLSetCurrentContext(prev);
    return e == GL_NO_ERROR ? 0 : 1;
}
