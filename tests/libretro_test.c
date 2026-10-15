/* A small libretro frontend for tests/libretro_test.py: opens the core, loads CONTENT, plays FRAMES frames pressing
 * START and A now and then, and says what came out.
 *   libretro_test CORE CONTENT SAVES|- FRAMES
 * -> "frames N samples S varied 0|1 crc X" (X: the last picture's FNV-1a); exit 1 if the core refused the content. */
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

static const char *saves;
static unsigned frame, w, h;
static long samples;
static int varied;
static uint32_t crc;
static int shut;

static void log_line(enum retro_log_level level, const char *fmt, ...) {
    (void)level;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

static bool env(unsigned cmd, void *data) {
    switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: return *(enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_RGB565;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *(const char **)data = saves; return saves != NULL;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: ((struct retro_log_callback *)data)->log = log_line; return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: return true;
    case RETRO_ENVIRONMENT_SHUTDOWN: shut = 1; return true;
    default: return false;
    }
}

static void video(const void *data, unsigned width, unsigned height, size_t pitch) {
    w = width, h = height, crc = 2166136261u, varied = 0;
    const uint16_t *first = data;
    for (unsigned y = 0; y < height; y++) {
        const uint16_t *row = (const uint16_t *)((const uint8_t *)data + y * pitch);
        for (unsigned x = 0; x < width; x++) {
            crc = (crc ^ (row[x] & 0xff)) * 16777619u, crc = (crc ^ (row[x] >> 8)) * 16777619u;
            varied |= row[x] != *first;
        }
    }
}

static size_t audio(const int16_t *data, size_t n) { return (void)data, samples += (long)n, n; }
static void poll(void) {}
static int16_t input(unsigned port, unsigned device, unsigned index, unsigned id) {
    (void)index;
    if (port || device != RETRO_DEVICE_JOYPAD) return 0;
    if (id == RETRO_DEVICE_ID_JOYPAD_START) return frame % 60 >= 30 && frame % 60 < 34;
    if (id == RETRO_DEVICE_ID_JOYPAD_A) return frame % 90 >= 45 && frame % 90 < 49;
    return 0;
}

#define FN(ret, name, ...) ret (*name)(__VA_ARGS__) = (ret(*)(__VA_ARGS__))dlsym(core, #name)

int main(int argc, char **argv) {
    if (argc != 5) return fprintf(stderr, "libretro_test CORE CONTENT SAVES|- FRAMES\n"), 2;
    void *core = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!core) return fprintf(stderr, "%s\n", dlerror()), 2;
    saves = strcmp(argv[3], "-") ? argv[3] : NULL;
    FN(unsigned, retro_api_version, void);
    FN(void, retro_get_system_info, struct retro_system_info *);
    FN(void, retro_get_system_av_info, struct retro_system_av_info *);
    FN(void, retro_set_environment, retro_environment_t);
    FN(void, retro_set_video_refresh, retro_video_refresh_t);
    FN(void, retro_set_audio_sample_batch, retro_audio_sample_batch_t);
    FN(void, retro_set_input_poll, retro_input_poll_t);
    FN(void, retro_set_input_state, retro_input_state_t);
    FN(void, retro_init, void);
    FN(void, retro_deinit, void);
    FN(bool, retro_load_game, const struct retro_game_info *);
    FN(void, retro_unload_game, void);
    FN(void, retro_run, void);
    if (!retro_api_version || !retro_run || !retro_deinit || retro_api_version() != RETRO_API_VERSION)
        return fprintf(stderr, "not a libretro core\n"), 2;
    if (dlsym(core, "game_init")) return fprintf(stderr, "the core exports the engine's names\n"), 2;
    struct retro_system_info si;
    retro_get_system_info(&si);
    fprintf(stderr, "%s %s (%s)\n", si.library_name, si.library_version, si.valid_extensions);
    retro_set_environment(env);
    retro_set_video_refresh(video);
    retro_set_audio_sample_batch(audio);
    retro_set_input_poll(poll);
    retro_set_input_state(input);
    retro_init();
    struct retro_game_info game = {argv[2], NULL, 0, NULL};
    if (!retro_load_game(&game)) return puts("refused"), 1;
    struct retro_system_av_info av;
    retro_get_system_av_info(&av);
    int frames = atoi(argv[4]);
    for (frame = 0; (int)frame < frames && !shut; frame++) retro_run();
    printf("frames %u samples %ld varied %d crc %08x size %ux%u fps %g hz %g\n", frame, samples, varied, crc, w, h,
           av.timing.fps, av.timing.sample_rate);
    retro_unload_game();
    retro_deinit();
    dlclose(core);
    return 0;
}
