#pragma once
#include <stdint.h>

typedef struct AuraMPV AuraMPV;
AuraMPV *aura_mpv_create(const char *library_path);
AuraMPV *aura_mpv_create_recorder(const char *library_path);
void aura_mpv_destroy(AuraMPV *player);
int aura_mpv_command(AuraMPV *player, const char *const *arguments);
int aura_mpv_set_string(AuraMPV *player, const char *name, const char *value);
double aura_mpv_get_number(AuraMPV *player, const char *name);
char *aura_mpv_get_string(AuraMPV *player, const char *name);
void aura_mpv_free_string(AuraMPV *player, char *value);
int aura_mpv_poll(AuraMPV *player);
int aura_mpv_init_gl(AuraMPV *player);
void aura_mpv_set_render_callback(AuraMPV *player, void (*callback)(void *), void *context);
int aura_mpv_needs_frame(AuraMPV *player);
void aura_mpv_render(AuraMPV *player, int width, int height);
void aura_mpv_render_window(AuraMPV *player, int width, int height);
void aura_mpv_report_swap(AuraMPV *player);
void aura_mpv_uninit_gl(AuraMPV *player);
