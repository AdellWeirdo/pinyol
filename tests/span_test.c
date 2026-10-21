/* span_mix_const (gfx_span.c) gives the pixels the general mixing gives (mix565, blend_held in gfx_px.h): every pixel under,
 * a spread of colours and alphas, every mode, both byte orders. tests/pie/ runs the same check on the ESP32-S3's vector code. */
#include <stdio.h>

#include "gfx_px.h"
#include "gfx_span.h"

static uint16_t want(uint16_t d, uint16_t c, unsigned a, int mode) {
    if (mode == BLEND_ALPHA) {
        uint32_t k = (a + 4) >> 3, dd = (d | (uint32_t)d << 16) & 0x07E0F81Fu, cc = (c | (uint32_t)c << 16) & 0x07E0F81Fu;
        uint32_t m = ((cc * k + dd * (32 - k)) >> 5) & 0x07E0F81Fu;
        return (uint16_t)(m | m >> 16); /* mix565 without its canvas-key step (span_mix_const is not for canvases) */
    }
    return blend_held(d, c, a, mode);
}

int main(void) {
    static uint16_t run[65536];
    const uint16_t colours[] = {0x0000, 0xFFFF, 0xF800, 0x07E0, 0x001F, 0x8410, 0x1234, 0xBEEF, 0x7BEF, 0xF81F};
    const unsigned alphas[] = {0, 1, 3, 4, 5, 64, 100, 127, 128, 200, 252, 255, 256};
    long bad = 0;
    for (int mode = BLEND_ALPHA; mode <= BLEND_QUARTER; mode++)
        for (size_t ci = 0; ci < sizeof colours / sizeof *colours; ci++)
            for (size_t ai = 0; ai < sizeof alphas / sizeof *alphas; ai++)
                for (int swap = 0; swap < 2; swap++) {
                    for (int d = 0; d < 65536; d++) run[d] = swap ? bswap16((uint16_t)d) : (uint16_t)d;
                    span_mix_const(run, 65536, colours[ci], alphas[ai], mode, swap);
                    for (int d = 0; d < 65536; d++) {
                        uint16_t got = swap ? bswap16(run[d]) : run[d], w = want((uint16_t)d, colours[ci], alphas[ai], mode);
                        if (got != w && bad++ < 5)
                            printf("mode %d c %04x a %u swap %d d %04x: %04x, want %04x\n", mode, colours[ci], alphas[ai], swap, d, got, w);
                    }
                }
    printf(bad ? "span_test: %ld pixels differ\n" : "span_test: ok\n", bad);
    return bad != 0;
}
