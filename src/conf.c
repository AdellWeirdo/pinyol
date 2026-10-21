/* The console's settings (conf.h): a small JSON file in the platform's folder, and the colour filter's table.
 *
 * The colour filter shifts the colours a protanope, deuteranope or tritanope cannot tell apart (daltonization, as
 * Fidaner, Lin and Okur did it, 2005): what that player would see is simulated with Machado, Oliveira and Fernandes's
 * matrices (IEEE TVCG 2009, severity 1), the difference from the real colour is the part they miss, and it is added
 * back on the channels they do see. Worked out once for every RGB555 (the picture's 65536 colours less a green bit,
 * 64 KB in slow memory), then a lookup a pixel. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"
#include "conf.h"

conf_t CONF;
static uint16_t *lut; /* RGB555 -> RGB565 through the filter, while one is on */
static int lut_colour;

static const conf_t DEFAULTS = {.volume = 100, .reduce_flash = false, .colour = 0, .speed = 100, .lang = CONF_ES, .swap_ab = false};
static const char *const LANGS[] = {"es", "ca", "en"};
static const char *const COLOURS[] = {"normal", "protan", "deutan", "tritan"};

const char *conf_lang_code(void) { return LANGS[CONF.lang]; }

static bool conf_path(char *p, size_t n) {
    char dir[384];
    if (!hal_console_dir(dir, sizeof dir)) return false;
    snprintf(p, n, "%s/settings.json", dir);
    return true;
}

bool conf_set(const char *key, const char *value) {
    if (!key || !value) return false;
    if (!strcmp(key, "volume")) {
        int v = atoi(value);
        if (v < 0 || v > 100 || (v == 0 && strcmp(value, "0"))) return false;
        CONF.volume = v;
    } else if (!strcmp(key, "flash")) {
        if (!strcmp(value, "less") || !strcmp(value, "true")) CONF.reduce_flash = true;
        else if (!strcmp(value, "normal") || !strcmp(value, "false")) CONF.reduce_flash = false;
        else return false;
    } else if (!strcmp(key, "colour") || !strcmp(key, "color")) {
        int i = 0;
        while (i < 4 && strcmp(COLOURS[i], value)) i++;
        if (i == 4) return false;
        CONF.colour = i;
    } else if (!strcmp(key, "speed")) {
        int v = atoi(value);
        if (v != 100 && v != 75 && v != 50) return false;
        CONF.speed = v;
    } else if (!strcmp(key, "lang")) {
        int i = 0;
        while (i < 3 && strcmp(LANGS[i], value)) i++;
        if (i == 3) return false;
        CONF.lang = i;
    } else if (!strcmp(key, "swap_ab")) {
        if (!strcmp(value, "true")) CONF.swap_ab = true;
        else if (!strcmp(value, "false")) CONF.swap_ab = false;
        else return false;
    } else {
        return false;
    }
    conf_apply();
    return true;
}

void conf_load(void) {
    CONF = DEFAULTS;
    char p[400];
    if (conf_path(p, sizeof p)) {
        char *txt = read_file(p, NULL);
        cJSON *j = txt ? cJSON_Parse(txt) : NULL;
        free(txt);
        if (cJSON_IsObject(j)) {
            if (cJSON_IsNumber(jget(j, "volume"))) {
                const int v = jget(j, "volume")->valueint;
                CONF.volume = v < 0 ? 0 : v > 100 ? 100 : v;
            }
            if (cJSON_IsBool(jget(j, "reduce_flash"))) CONF.reduce_flash = cJSON_IsTrue(jget(j, "reduce_flash"));
            if (jstr(j, "colour")) conf_set("colour", jstr(j, "colour"));
            if (cJSON_IsNumber(jget(j, "speed"))) {
                const int v = jget(j, "speed")->valueint;
                if (v == 100 || v == 75 || v == 50) CONF.speed = v;
            }
            if (jstr(j, "lang")) conf_set("lang", jstr(j, "lang"));
            if (cJSON_IsBool(jget(j, "swap_ab"))) CONF.swap_ab = cJSON_IsTrue(jget(j, "swap_ab"));
        }
        cJSON_Delete(j);
    }
    conf_apply();
}

void conf_save(void) {
    char p[400];
    if (!conf_path(p, sizeof p)) return;
    char txt[256];
    snprintf(txt, sizeof txt, "{\"volume\": %d, \"reduce_flash\": %s, \"colour\": \"%s\", \"speed\": %d, \"lang\": \"%s\", \"swap_ab\": %s}\n",
             CONF.volume, CONF.reduce_flash ? "true" : "false", COLOURS[CONF.colour], CONF.speed, LANGS[CONF.lang],
             CONF.swap_ab ? "true" : "false");
    static char written[256]; /* the same again is not written (on the console's flash a write stalls both cores) */
    if (!strcmp(txt, written)) return;
    if (save_file_atomic(p, txt)) snprintf(written, sizeof written, "%s", txt);
    else hal_log("settings: cannot write %s", p);
}

/* ------------------------------------------------------------------ the colour filter */

static const float SIM[4][9] = {
    {1, 0, 0, 0, 1, 0, 0, 0, 1},
    {0.152286f, 1.052583f, -0.204868f, 0.114503f, 0.786281f, 0.099216f, -0.003882f, -0.048116f, 1.051998f},  /* protanopia */
    {0.367322f, 0.860646f, -0.227968f, 0.280085f, 0.672501f, 0.047413f, -0.011820f, 0.042940f, 0.968881f},   /* deuteranopia */
    {1.255528f, -0.076749f, -0.178779f, -0.078411f, 0.930809f, 0.147602f, 0.004733f, 0.691367f, 0.303900f},  /* tritanopia */
};

static float to_linear(float s) { return s <= 0.04045f ? s / 12.92f : powf((s + 0.055f) / 1.055f, 2.4f); }
static float to_srgb(float l) { return l <= 0.0031308f ? l * 12.92f : 1.055f * powf(l, 1 / 2.4f) - 0.055f; }

static void build_lut(int colour) {
    if (!lut) lut = hal_realloc_slow(NULL, 32768 * sizeof *lut);
    if (!lut) return;
    float lin5[32], lin_out[1025];
    for (int i = 0; i < 32; i++) lin5[i] = to_linear(i / 31.0f);
    for (int i = 0; i <= 1024; i++) lin_out[i] = to_srgb(i / 1024.0f);
    const float *m = SIM[colour];
    for (int c = 0; c < 32768; c++) {
        const float r = lin5[c >> 10], g = lin5[c >> 5 & 31], b = lin5[c & 31];
        const float sr = m[0] * r + m[1] * g + m[2] * b, sg = m[3] * r + m[4] * g + m[5] * b, sb = m[6] * r + m[7] * g + m[8] * b;
        const float er = r - sr, eg = g - sg, eb = b - sb; /* what that player misses */
        float o[3] = {r, g + 0.7f * er + eg, b + 0.7f * er + eb};
        int v[3];
        for (int k = 0; k < 3; k++) {
            float x = o[k] < 0 ? 0 : o[k] > 1 ? 1 : o[k];
            v[k] = (int)(lin_out[(int)(x * 1024)] * 255 + 0.5f);
        }
        lut[c] = (uint16_t)((v[0] >> 3) << 11 | (v[1] >> 2) << 5 | (v[2] >> 3));
    }
    lut_colour = colour;
}

bool conf_filter_on(void) { return CONF.colour != CONF_COLOUR_NORMAL && lut; }

void conf_filter(uint16_t *px, int n) {
    if (!conf_filter_on()) return;
    for (int i = 0; i < n; i++) {
        const uint16_t v = px[i];
        px[i] = lut[(v >> 1 & 0x7FE0) | (v & 31)]; /* RGB565 -> RGB555: the low green bit dropped */
    }
}

void conf_free(void) { /* a game ended: the filter's table let go (conf_load makes it again for the next) */
    free(lut), lut = NULL;
}

void conf_apply(void) {
    audio_user((float)CONF.volume / 100);
    if (CONF.colour == CONF_COLOUR_NORMAL) {
        free(lut), lut = NULL;
    } else if (!lut || lut_colour != CONF.colour) {
        build_lut(CONF.colour);
    }
}
