/* Not a test: how long the mixer takes for a second of sound, scene by scene, on this machine (cmake target audio_bench).
 * The console is far slower; what carries over is the order and the ratios between scenes. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "bp.h"

static int16_t out[2 * AUDIO_HZ];

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

static void clip(const char *id) {
    int16_t *c = malloc(sizeof(int16_t) * 20000);
    for (int i = 0; i < 20000; i++) c[i] = (int16_t)((i * 37) % 6000 - 3000);
    audio_sfx_set(id, c, 20000);
}

static void run(const char *what, const sfx_opts *o, int voices, int room, bool stereo) {
    audio_reset();
    clip("C");
    audio_reverb(room, room < 0 ? 0 : 0.7f, 0, 0);
    for (int i = 0; i < voices; i++) audio_sfx_play_opts("C", o);
    audio_mix_stereo(out, 4000); /* (the wet level's ramp and the first blocks) */
    double t = now();
    for (int k = 0; k < 10; k++) stereo ? audio_mix_stereo(out, AUDIO_HZ) : audio_mix(out, AUDIO_HZ);
    printf("%-44s %6.2f ms per second of sound\n", what, (now() - t) * 100);
}

int main(void) {
    sfx_opts plain = {.gain = 0.2f, .pitch = 1, .loop = true};
    sfx_opts pitched = {.gain = 0.2f, .pitch = 1.3f, .loop = true};
    sfx_opts fancy = {.gain = 0.2f, .pitch = 1, .loop = true, .pan = 0.4f, .env = true, .attack = 0.01f, .sustain = 0.8f, .release = 0.1f, .reverb = 0.5f};
    run("nothing playing", &plain, 0, -1, true);
    run("12 plain voices", &plain, 12, -1, true);
    run("12 voices at pitch 1.3", &pitched, 12, -1, true);
    run("12 voices: pan, envelope, reverb send (no room)", &fancy, 12, -1, true);
    run("12 plain voices, room", &plain, 12, reverb_find("room"), true);
    run("12 fancy voices, hall", &fancy, 12, reverb_find("hall"), true);
    run("12 fancy voices, space_echo", &fancy, 12, reverb_find("space_echo"), true);
    return 0;
}
