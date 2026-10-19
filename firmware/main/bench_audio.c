/* -DBP_BENCH=audio: what the sound costs on the board. The real audio output (codec, I2S, the mixing task on core 1) with
 * voices started from here, and the share of a core the mixer takes over a few seconds for each mix: nothing, plain voices,
 * pitched voices, instruments (envelope, loop region), PSG tones with vibrato and a wave table, and everything with the
 * GBA reverb. Lines start with "BENCH audio". audio_out_mix_us is the time in audio_mix(), summed (audio_out.c). */
#include "bench.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_out.h"
#include "bp.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "input.h"
#include "studio_synth.h"

#define LOG(...) (printf("BENCH audio " __VA_ARGS__), putchar('\n'))
#define SECONDS 4

static const uint8_t BASS[32] = {8, 10, 12, 14, 15, 14, 12, 10, 8, 6, 4, 2, 0, 2, 4, 6, 8, 10, 12, 14, 15, 14, 12, 10, 8, 6, 4, 2, 0, 2, 4, 6};
static int handles[12];
static int nhandles;

static void measure(const char *name) {
    vTaskDelay(pdMS_TO_TICKS(300)); /* let the voices start and the first blocks go */
    int64_t t0 = esp_timer_get_time();
    audio_out_mix_us = 0, audio_out_blocks = 0, audio_out_underruns = 0, audio_out_mix_min_us = INT32_MAX, audio_out_mix_max_us = 0;
    vTaskDelay(pdMS_TO_TICKS(SECONDS * 1000));
    int64_t dt = esp_timer_get_time() - t0, us = audio_out_mix_us;
    int blocks = audio_out_blocks;
    const double block_us = 256.0 * 1e6 / AUDIO_HZ; /* what a block of sound lasts: the budget for mixing it */
    /* min: the mixer with nothing in its way (the cost); mean and max include the task being preempted on core 1 */
    LOG("%-44s min %5.2f %% | mean %5.2f %% | max %5.2f %% of a core | %d blocks | %d underruns", name,
        100.0 * audio_out_mix_min_us / block_us, 100.0 * (double)us / (double)dt, 100.0 * audio_out_mix_max_us / block_us, blocks,
        audio_out_underruns);
}

static void stop_all(void) {
    for (int i = 0; i < nhandles; i++) audio_sfx_stop(handles[i]);
    nhandles = 0;
    for (int v = 0; v < PSG_VOICES; v++) psg_release(v);
    vTaskDelay(pdMS_TO_TICKS(400));
    psg_reset();
    studio_fx_params fx;
    studio_fx_get(&fx);
    fx.reverb = STUDIO_PLATE, fx.lofi = false;
    studio_fx_set(&fx);
    studio_fx_reset();
}

static void voices(int n, float pitch, bool inst, float send_r) {
    for (int i = 0; i < n && nhandles < 12; i++) {
        voice_opts o = {.gain = 0.3f, .pitch = pitch * (1.0f + 0.05f * (float)i), .loop = true, .first_variant = true, .send_r = send_r};
        if (inst) {
            o.adsr = true, o.a = 441, o.d = 3307, o.s = 0.6f, o.r = 7717;
            o.loop_from = 1002, o.loop_to = AUDIO_HZ;
        }
        handles[nhandles++] = audio_voice_play("BKEYS", &o);
    }
}

static void tones(int n, bool vib) {
    for (int v = 0; v < n && v < PSG_VOICES; v++) {
        psg_note p = {.wave = PSG_WAVE, .freq = 110.0f * (float)(v + 1), .vol = 0.4f, .duty = 0.5f, .sustain = 1, .release = 0.03f};
        memcpy(p.table, BASS, 32);
        if (vib) p.vib_depth = 15, p.vib_speed = 5.5f;
        psg_play(v, &p);
    }
}

void bench_audio_run(void) {
    vTaskDelay(pdMS_TO_TICKS(4000)); /* time for the USB log to be reopened after the flash's reset */
    LOG("start | CPU %d MHz | free internal %u KB, PSRAM %u KB", CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ,
        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024), (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    if (!audio_out_init(input_bus())) return (void)LOG("no audio output: nothing to measure");
    /* the clip the toy makes: one second of a filtered saw at 220 Hz */
    synth_params sp;
    synth_defaults(&sp);
    sp.wave = PSG_SAW, sp.freq = 220, sp.sustain = 1, sp.decay = 0, sp.lowpass = 0.55f, sp.volume = 0.6f;
    int16_t *pcm = heap_caps_malloc(sizeof(int16_t) * (AUDIO_HZ + 64), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    int n = pcm ? synth_render(&sp, pcm, AUDIO_HZ + 64) : 0;
    if (n < 100 || !audio_sfx_set("BKEYS", pcm, n)) return (void)LOG("could not make the clip");
    LOG("clip: %d samples; 12 sample voices, 4 PSG voices, then 2 echoes", n);

    measure("idle (no voice), right after boot");
    vTaskDelay(pdMS_TO_TICKS(12000)); /* the effects stop costing after 8 s with nothing sent (studio_fx.c) */
    measure("idle (no voice), 12 s later");
    voices(4, 1.0f, false, 0), measure("4 sample voices, as recorded (fast path)"), stop_all();
    voices(12, 1.0f, false, 0), measure("12 sample voices, as recorded"), stop_all();
    voices(8, 1.3f, false, 0), measure("8 sample voices, pitched (interpolated)"), stop_all();
    voices(4, 1.3f, true, 0), measure("4 instrument notes (envelope, loop region)"), stop_all();
    voices(8, 1.3f, true, 0), measure("8 instrument notes"), stop_all();
    voices(12, 1.3f, true, 0), measure("12 instrument notes"), stop_all();
    tones(4, false), measure("4 PSG tones, wave table"), stop_all();
    tones(4, true), measure("4 PSG tones, wave table + vibrato"), stop_all();
    {
        studio_fx_params fx;
        studio_fx_get(&fx);
        fx.reverb = STUDIO_GBA, fx.size = 0.6f, fx.lofi = true;
        studio_fx_set(&fx);
        voices(4, 1.3f, true, 0.5f), measure("4 instruments + GBA reverb + lo-fi"), stop_all();
        studio_fx_get(&fx);
        fx.reverb = STUDIO_GBA, fx.size = 0.6f, fx.lofi = true;
        studio_fx_set(&fx);
        voices(8, 1.3f, true, 0.5f), tones(4, true), measure("8 instruments + 4 tones + GBA reverb + lo-fi"), stop_all();
    }
    {
        studio_fx_params fx;
        studio_fx_get(&fx);
        fx.reverb = STUDIO_PLATE, fx.size = 0.5f, fx.damp = 0.3f, fx.lofi = false;
        studio_fx_set(&fx);
        voices(4, 1.3f, true, 0.5f), measure("4 instruments + plate reverb"), stop_all();
    }
    vTaskDelay(pdMS_TO_TICKS(12000));
    measure("idle again after everything, 12 s on");
    LOG("done");
}
