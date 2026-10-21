/* span_mix_const's vector code against span_mix_const_c: random runs at every alignment and length, every mode, both byte
 * orders, alphas across 0..256. Prints PIE ok or the first differences, then PIE_DONE (tests/pie/run.sh reads it). */
#include <stdio.h>
#include <string.h>

#include "gfx_span.h"

static uint32_t seed = 12345;
static uint32_t rnd(void) { return seed = seed * 1664525u + 1013904223u; }

void app_main(void) {
    static uint16_t a[600] __attribute__((aligned(16))), b[600] __attribute__((aligned(16)));
    long bad = 0, runs = 0;
    for (int it = 0; it < 4000; it++) {
        const int off = (int)(rnd() % 16), n = (int)(rnd() % 400), mode = (int)(rnd() % 4), swap = (int)(rnd() & 1);
        const unsigned alpha = it % 7 == 0 ? (unsigned[]){0, 1, 4, 128, 252, 255, 256}[it / 7 % 7] : rnd() % 257;
        const uint16_t c = (uint16_t)rnd();
        for (int i = 0; i < 600; i++) a[i] = b[i] = (uint16_t)rnd();
        span_mix_const(a + off, n, c, alpha, mode, swap);
        span_mix_const_c(b + off, n, c, alpha, mode, swap);
        runs++;
        if (memcmp(a, b, sizeof a)) {
            for (int i = 0; i < 600; i++)
                if (a[i] != b[i] && bad++ < 8)
                    printf("diff: off %d n %d mode %d swap %d alpha %u c %04x at %d: %04x want %04x\n", off, n, mode, swap, alpha,
                           c, i - off, a[i], b[i]);
        }
    }
    printf(bad ? "PIE %ld pixels differ in %ld runs\n" : "PIE ok, %ld runs\n", bad ? bad : runs, runs);
    printf("PIE_DONE\n");
}
