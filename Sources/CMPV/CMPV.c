// Dynamic adapter to libmpv's public client/render API (https://mpv.io/).
// No dependency on a global mpv installation; release builds bundle the dylibs.
#include "CMPV.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <OpenGL/gl3.h>

typedef struct { int type; void *data; } render_param;
typedef struct { void *(*get_proc_address)(void *, const char *); void *ctx; } gl_init;
typedef struct { int fbo, w, h, internal_format; } gl_fbo;
typedef struct { int event_id, error; uint64_t userdata; void *data; } mpv_event;
typedef struct { int reason, error; } end_file;

struct AuraMPV {
    void *library, *mpv, *render;
    void *(*create)(void);
    int (*initialize)(void *);
    int (*option)(void *, const char *, const char *);
    void (*terminate)(void *);
    int (*command)(void *, const char *const *);
    int (*set)(void *, const char *, const char *);
    int (*get)(void *, const char *, int, void *);
    char *(*string)(void *, const char *);
    void (*free)(void *);
    mpv_event *(*wait)(void *, double);
    int (*render_create)(void **, void *, render_param *);
    void (*render_free)(void *);
    int (*render_frame)(void *, render_param *);
    uint64_t (*render_update)(void *);
    void (*render_callback)(void *, void (*)(void *), void *);
    void (*swap)(void *);
};

#define LOAD(member, symbol) p->member = dlsym(p->library, symbol); if (!p->member) goto fail
static AuraMPV *create_player(const char *path, int recorder) {
    AuraMPV *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!p->library) goto fail;
    LOAD(create, "mpv_create"); LOAD(initialize, "mpv_initialize");
    LOAD(option, "mpv_set_option_string"); LOAD(terminate, "mpv_terminate_destroy");
    LOAD(command, "mpv_command"); LOAD(set, "mpv_set_property_string");
    LOAD(get, "mpv_get_property"); LOAD(string, "mpv_get_property_string");
    LOAD(free, "mpv_free"); LOAD(wait, "mpv_wait_event");
    LOAD(render_create, "mpv_render_context_create"); LOAD(render_free, "mpv_render_context_free");
    LOAD(render_frame, "mpv_render_context_render"); LOAD(render_update, "mpv_render_context_update");
    LOAD(swap, "mpv_render_context_report_swap");
    LOAD(render_callback, "mpv_render_context_set_update_callback");
    p->mpv = p->create(); if (!p->mpv) goto fail;
    p->option(p->mpv, "config", "no");
    p->option(p->mpv, "vo", recorder ? "null" : "libmpv");
    if (recorder) p->option(p->mpv, "ao", "null");
    // Prefer IOSurface-backed GPU frames; retain the copy path when interop
    // is unavailable, then let mpv fall back to software for unsupported media.
    p->option(p->mpv, "hwdec", "videotoolbox,videotoolbox-copy");
    // Display-link pacing handles presentation. Do not sleep while holding
    // AppKit's shared CGL context lock (see libmpv render API timing docs).
    p->option(p->mpv, "video-timing-offset", "0");
    p->option(p->mpv, "idle", "yes");
    p->option(p->mpv, "keep-open", "yes");
    p->option(p->mpv, "input-default-bindings", "no");
    p->option(p->mpv, "input-vo-keyboard", "no");
    p->option(p->mpv, "osc", "no");
    p->option(p->mpv, "osd-level", "0");
    p->option(p->mpv, "terminal", "no");
    p->option(p->mpv, "ytdl", "no");
    p->option(p->mpv, "network-timeout", "15");
    p->option(p->mpv, "cache", "yes");
    p->option(p->mpv, "demuxer-max-bytes", "256MiB");
    p->option(p->mpv, "demuxer-max-back-bytes", "64MiB");
    p->option(p->mpv, "cache-secs", "30");
    p->option(p->mpv, "cache-pause-wait", "3");
    p->option(p->mpv, "hls-bitrate", "max");
    p->option(p->mpv, "user-agent", "Aura/1.0");
    p->option(p->mpv, "sub-auto", "fuzzy");
    p->option(p->mpv, "slang", "tr,tur,en,eng");
    p->option(p->mpv, "alang", "tr,tur,en,eng");
    p->option(p->mpv, "sub-font", "Helvetica Neue");
    p->option(p->mpv, "sub-font-size", "42");
    p->option(p->mpv, "sub-border-size", "2");
    p->option(p->mpv, "sub-shadow-offset", "1");
    if (p->initialize(p->mpv) < 0) goto fail;
    return p;
fail:
    if (p->mpv && p->terminate) p->terminate(p->mpv);
    if (p->library) dlclose(p->library);
    free(p); return NULL;
}
AuraMPV *aura_mpv_create(const char *path) { return create_player(path, 0); }
AuraMPV *aura_mpv_create_recorder(const char *path) { return create_player(path, 1); }
void aura_mpv_destroy(AuraMPV *p) { if (!p) return; if (p->render) p->render_free(p->render); p->terminate(p->mpv); dlclose(p->library); free(p); }
int aura_mpv_command(AuraMPV *p, const char *const *a) { return p ? p->command(p->mpv, a) : -1; }
int aura_mpv_set_string(AuraMPV *p, const char *n, const char *v) { return p ? p->set(p->mpv, n, v) : -1; }
double aura_mpv_get_number(AuraMPV *p, const char *n) { double d = 0; if (p) p->get(p->mpv, n, 5, &d); return d; }
char *aura_mpv_get_string(AuraMPV *p, const char *n) { return p ? p->string(p->mpv, n) : NULL; }
void aura_mpv_free_string(AuraMPV *p, char *v) { if (p && v) p->free(v); }
int aura_mpv_poll(AuraMPV *p) {
    if (!p) return 0;
    int result = 0;
    for (int i = 0; i < 100; ++i) {
        mpv_event *e = p->wait(p->mpv, 0);
        if (!e || !e->event_id) break;
        if (e->event_id == 8) result = 2;
        if (e->event_id == 7 && e->data) {
            end_file *end = e->data;
            if (end->reason == 4) result = -1;
            else if (end->reason == 0) result = 1;
        }
    }
    return result;
}
static void *get_proc(void *ctx, const char *name) { return dlsym(RTLD_DEFAULT, name); }
int aura_mpv_init_gl(AuraMPV *p) {
    if (!p || p->render) return p && p->render ? 0 : -1;
    gl_init init = { get_proc, NULL };
    render_param params[] = {{1, "opengl"}, {2, &init}, {0, NULL}};
    return p->render_create(&p->render, p->mpv, params);
}
void aura_mpv_set_render_callback(AuraMPV *p, void (*callback)(void *), void *context) { if (p && p->render) p->render_callback(p->render, callback, context); }
int aura_mpv_needs_frame(AuraMPV *p) { return p && p->render && (p->render_update(p->render) & 1); }
void aura_mpv_render(AuraMPV *p, int width, int height) {
    if (!p || !p->render || width < 1 || height < 1) return;
    GLint fbo; glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
    gl_fbo target = {fbo, width, height, 0}; int flip = 1;
    render_param params[] = {{3, &target}, {4, &flip}, {0, NULL}};
    p->render_frame(p->render, params);
}
void aura_mpv_render_window(AuraMPV *p, int width, int height) { glBindFramebuffer(GL_FRAMEBUFFER, 0); aura_mpv_render(p, width, height); }
void aura_mpv_report_swap(AuraMPV *p) { if (p && p->render) p->swap(p->render); }
void aura_mpv_uninit_gl(AuraMPV *p) { if (p && p->render) { p->render_free(p->render); p->render = NULL; } }
