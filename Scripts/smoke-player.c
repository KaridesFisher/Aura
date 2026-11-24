#include "CMPV.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    AuraMPV *mpv = aura_mpv_create_recorder(argv[1]);
    if (!mpv) { puts("FAIL mpv initialize"); return 1; }
    aura_mpv_set_string(mpv, "stream-record", argv[3]);
    const char *cmd[] = {"loadfile", argv[2], "replace", NULL};
    if (aura_mpv_command(mpv, cmd) < 0) return 1;
    double position = 0;
    for (int i = 0; i < 160; i++) { usleep(25000); aura_mpv_poll(mpv); position = aura_mpv_get_number(mpv, "time-pos"); }
    double duration = aura_mpv_get_number(mpv, "duration");
    double tracks = aura_mpv_get_number(mpv, "track-list/count");
    const char *stop[] = {"stop", NULL}; aura_mpv_command(mpv, stop);
    aura_mpv_destroy(mpv);
    struct stat st; int exists = stat(argv[3], &st) == 0;
    printf("position=%.2f duration=%.2f tracks=%.0f recording_bytes=%lld\n", position, duration, tracks, exists ? (long long)st.st_size : 0);
    int passed = position > 1 && duration > 10 && tracks >= 2 && exists && st.st_size > 10000;
    puts(passed ? "PASS real decode and MKV recording" : "FAIL playback/recording");
    return passed ? 0 : 1;
}
