/* Tracker music (src/modplay.c): a small module made here plays at its pitch and fades out; broken modules, made by
 * damaging it at random, are refused or play without reading outside the file (run under ASan in Debug). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

static int failures, checks;
#define CHECK(c)                                                                  \
    do {                                                                          \
        checks++;                                                                 \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

#define PATH "mod_test.mod"
static float buf[AUDIO_HZ];

static int make_mod(uint8_t *m) { /* one pattern, C-2 on channel 0 with sample 1: a looped 32-byte square wave */
    memset(m, 0, 1084 + 1024 + 32);
    memcpy(m, "np2d test", 9);
    uint8_t *s = m + 20;
    s[23] = 16, s[25] = 64, s[29] = 16;    /* length 16 words, volume 64, loop from 0, 16 words long */
    m[950] = 1, m[951] = 127;              /* one position in the order, playing pattern 0 */
    memcpy(m + 1080, "M.K.", 4);
    uint8_t *cell = m + 1084;              /* row 0, channel 0: sample 1, period 428 */
    cell[0] = 428 >> 8, cell[1] = 428 & 0xFF, cell[2] = 1 << 4;
    for (int i = 0; i < 32; i++) m[1084 + 1024 + i] = (uint8_t)(i < 16 ? 100 : -100);
    return 1084 + 1024 + 32;
}

static void put(const uint8_t *m, int n) {
    FILE *f = fopen(PATH, "wb");
    fwrite(m, 1, (size_t)n, f);
    fclose(f);
}

static void run(int n) {
    memset(buf, 0, sizeof buf);
    for (int off = 0; off < n; off += 256) mod_mix(buf + off, n - off < 256 ? n - off : 256);
}

int main(void) {
    static uint8_t mod[4096], bad[4096];
    int n = make_mod(mod);
    put(mod, n);
    CHECK(mod_play(PATH, 1));
    run(AUDIO_HZ);
    int crossings = 0;
    float peak = 0;
    for (int i = 1; i < AUDIO_HZ; i++) {
        crossings += (buf[i - 1] < 0) != (buf[i] < 0);
        peak = buf[i] > peak ? buf[i] : peak;
    }
    /* period 428 plays the sample at 7093789.2 / 856 = 8287 Hz: a 32-byte loop is a 259 Hz tone */
    CHECK(crossings > 500 && crossings < 540);
    CHECK(peak > 1000);
    mod_stop(100);
    run(AUDIO_HZ / 2);
    float tail = 0;
    for (int i = AUDIO_HZ / 4; i < AUDIO_HZ / 2; i++) tail += buf[i] < 0 ? -buf[i] : buf[i];
    CHECK(tail == 0 && !mod_playing());

    /* two crafted modules: a 15-sample one whose note names sample 16, and an order pointing past the file */
    static uint8_t old[600 + 1024 + 64];
    memset(old, 0, sizeof old);
    memcpy(old, "old mod", 7);
    old[470] = 1;                                               /* one position, pattern 0 */
    old[600] = 0x11, old[601] = 0xAC, old[602] = 0x00;          /* sample 16, period 428 */
    put(old, sizeof old);
    if (mod_play(PATH, 1)) run(AUDIO_HZ / 4);
    static uint8_t far[1084 + 1024 * 131];
    memcpy(far, mod, (size_t)n);
    far[950] = 2, far[952] = 0, far[953] = 130;
    put(far, 1084 + 1024 * 130 + 512);
    CHECK(!mod_play(PATH, 1)); /* pattern 130 would end past the file */

    put((const uint8_t *)"not a module", 12);
    CHECK(!mod_play(PATH, 1));

    srand(1);
    int played = 0;
    for (int k = 0; k < 20000; k++) { /* damage: a few bytes changed, and sometimes the file cut short */
        memcpy(bad, mod, (size_t)n);
        for (int j = 0; j < 1 + rand() % 8; j++) {
            int at = rand() % 1100;
            if (k % 3 == 0) at = 20 + rand() % 31 * 30 + 22 + rand() % 8; /* the sample lengths and loops */
            if (k % 5 == 0) at = 950 + rand() % 130;                      /* the order */
            bad[at] = (uint8_t)rand();
        }
        put(bad, k % 4 == 0 ? rand() % n : n);
        if (mod_play(PATH, 1)) played++, run(4096);
    }
    CHECK(played > 1000); /* most damaged ones still play (what they play does not matter, only that it is safe) */
    mod_reset();
    remove(PATH);
    printf("mod: %d checks, %d failed (%d damaged modules played)\n", checks, failures, played);
    return failures != 0;
}
