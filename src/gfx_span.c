/* One colour mixed into a run of pixels next to each other in memory: a box seen through (a fade, a dialogue's backing),
 * added (a flash) or taken away, the commonest full-screen mix. In C everywhere, and on the ESP32-S3 eight pixels at a
 * time with its vector unit (PIE) where the run is aligned. Both give the same pixels as gfx_quad.c's mixed_run (mix565,
 * add565_sat, sub565_sat); tests/pie/ checks the vector one against the C one in QEMU.
 *
 * The vector code follows Jet's RGB565ConstantBlend (github.com/CubeCoders/Jet, MIT, src/BlendSpans.cpp): each channel
 * taken apart with a 32-bit shift and a mask (both lanes at once), weighted with ee.vmul.u16, shifted back; a swapped
 * byte order turned with ee.vunzip.8 / ee.vzip.8. */
#include "gfx_span.h"

static inline unsigned ch_r(uint16_t v) { return v >> 11; }
static inline unsigned ch_g(uint16_t v) { return v >> 5 & 63; }
static inline unsigned ch_b(uint16_t v) { return v & 31; }
static inline uint16_t bswap(uint16_t v) { return (uint16_t)(v << 8 | v >> 8); }

/* The colour as each mode wants it, channel by channel: for alpha the colour times k and the weight of what is under
 * (32 - k), with k = (alpha + 4) / 8 as mix565; for the others the colour scaled by alpha as gfx_quad.c's ready(). */
typedef struct {
    int mode;
    unsigned w, r, g, b; /* alpha: under's weight and c's channels times k; add/sub: c's channels scaled */
} mix_t;

static mix_t prepare(uint16_t c, unsigned alpha, int mode) {
    mix_t m = {mode, 0, 0, 0, 0};
    if (mode == BLEND_ALPHA) {
        const unsigned k = (alpha + 4) >> 3;
        m.w = 32 - k, m.r = ch_r(c) * k, m.g = ch_g(c) * k, m.b = ch_b(c) * k;
    } else {
        const unsigned sh = mode == BLEND_QUARTER ? 10 : 8;
        m.r = ch_r(c) * alpha >> sh, m.g = ch_g(c) * alpha >> sh, m.b = ch_b(c) * alpha >> sh;
        if (m.r > 31) m.r = 31; /* (alpha is at most 256: only a full add reaches the top) */
        if (m.g > 63) m.g = 63;
        if (m.b > 31) m.b = 31;
    }
    return m;
}

static inline uint16_t mix1(uint16_t d, const mix_t *m) {
    unsigned r = ch_r(d), g = ch_g(d), b = ch_b(d);
    if (m->mode == BLEND_ALPHA) {
        r = (r * m->w + m->r) >> 5, g = (g * m->w + m->g) >> 5, b = (b * m->w + m->b) >> 5;
    } else if (m->mode == BLEND_SUB) {
        r = r > m->r ? r - m->r : 0, g = g > m->g ? g - m->g : 0, b = b > m->b ? b - m->b : 0;
    } else {
        r = r + m->r > 31 ? 31 : r + m->r, g = g + m->g > 63 ? 63 : g + m->g, b = b + m->b > 31 ? 31 : b + m->b;
    }
    return (uint16_t)(r << 11 | g << 5 | b);
}

static void mix_c(uint16_t *p, int n, const mix_t *m, bool swap) {
    for (int i = 0; i < n; i++) p[i] = swap ? bswap(mix1(bswap(p[i]), m)) : mix1(p[i], m);
}

void span_mix_const_c(uint16_t *p, int n, uint16_t c, unsigned alpha, int mode, bool swap) {
    const mix_t m = prepare(c, alpha, mode);
    mix_c(p, n, &m, swap);
}

#if PINYOL_PIE
/* Lanes of 8 x 16 bits, 16-byte aligned for ee.vld.128. */
typedef struct __attribute__((aligned(16))) {
    uint16_t mask5[8], mask6[8];  /* a channel's bits, and its top for the saturating modes */
    uint16_t w[8], ones[8];       /* alpha: under's weight; 1 (a multiply that only shifts, by SAR) */
    uint16_t r[8], g[8], b[8];    /* the colour's part, per channel */
} lanes_t;

static void fill8(uint16_t *l, unsigned v) {
    for (int i = 0; i < 8; i++) l[i] = (uint16_t)v;
}

#define STR(X) #X
#define XSTR(X) STR(X)
#define SAR(N) "movi %[tmp], " #N "\n\twsr %[tmp], sar\n\t"
/* q0: 8 pixels in, as RGB565; q7: out; q1: mask5; q4: mask6; q2: w; q3: ones. Each channel: apart into q5, mixed, back. */
#define PART(SH, MASK) SAR(SH) "ee.vsr.32 q5, q0\n\t" "ee.andq q5, q5, " #MASK "\n\t"
#define BACK(SH) SAR(SH) "ee.vsl.32 q5, q5\n\t"
#define ALPHA_CH(OFF) /* q5 = (q5 * w + colour) >> 5 */                                \
    SAR(0) "ee.vmul.u16 q5, q5, q2\n\t"                                            \
    "addi %[tmp], %[lanes], " XSTR(OFF) "\n\tee.vld.128.ip q6, %[tmp], 0\n\t"           \
    "ee.vadds.s16 q5, q5, q6\n\t" SAR(5) "ee.vmul.u16 q5, q5, q3\n\t"
#define ADD_CH(OFF, MASK) /* q5 = min(q5 + colour, top) */                         \
    "addi %[tmp], %[lanes], " XSTR(OFF) "\n\tee.vld.128.ip q6, %[tmp], 0\n\t"           \
    "ee.vadds.s16 q5, q5, q6\n\tee.vmin.s16 q5, q5, " #MASK "\n\t"
#define SUB_CH(OFF) /* q5 = max(q5 - colour, 0) */                                  \
    "addi %[tmp], %[lanes], " XSTR(OFF) "\n\tee.vld.128.ip q6, %[tmp], 0\n\t"           \
    "ee.vsubs.s16 q5, q5, q6\n\tee.zero.q q6\n\tee.vmax.s16 q5, q5, q6\n\t"
#define SWAP(Q) "ee.orq q5, " Q ", " Q "\n\tee.vunzip.8 " Q ", q5\n\tee.vzip.8 q5, " Q "\n\t" /* Q's bytes swapped, in Q */

/* offsets of the fields in lanes_t */
#define L_W 32
#define L_R 64
#define L_G 80
#define L_B 96

#define KERNEL(CH_R, CH_G, CH_B, SWAP_IN, SWAP_OUT)                                                        \
    __asm__ volatile("rsr %[saved], sar\n\t"                                                          \
                     "mov %[tmp], %[lanes]\n\tee.vld.128.ip q1, %[tmp], 16\n\tee.vld.128.ip q4, %[tmp], 16\n\t" \
                     "ee.vld.128.ip q2, %[tmp], 16\n\tee.vld.128.ip q3, %[tmp], 0\n\t"               \
                     "loopnez %[blocks], 1f\n\t"                                                       \
                     "ee.vld.128.ip q0, %[p], 0\n\t" SWAP_IN                                           \
                     PART(11, q1) CH_R BACK(11) "ee.orq q7, q5, q5\n\t"                               \
                     PART(5, q4) CH_G BACK(5) "ee.orq q7, q7, q5\n\t"                                 \
                     SAR(0) "ee.andq q5, q0, q1\n\t" CH_B "ee.orq q7, q7, q5\n\t" SWAP_OUT            \
                     "ee.vst.128.ip q7, %[p], 16\n\t"                                                  \
                     "1:\n\t"                                                                          \
                     "wsr %[saved], sar\n\t"                                                           \
                     : [saved] "=&r"(saved), [tmp] "=&r"(tmp), [blocks] "+&r"(blocks), [p] "+&r"(p)    \
                     : [lanes] "r"(&lanes)                                                             \
                     : "memory")

void span_mix_const(uint16_t *p, int n, uint16_t c, unsigned alpha, int mode, bool swap) {
    const mix_t m = prepare(c, alpha, mode);
    int head = (int)((16 - ((uintptr_t)p & 15)) & 15) / 2;
    if ((uintptr_t)p & 1 || n - head < 16) { /* odd address (never, for pixels) or too short to pay */
        mix_c(p, n, &m, swap);
        return;
    }
    mix_c(p, head, &m, swap);
    p += head, n -= head;
    int blocks = n / 8;
    const int tail = n - blocks * 8;
    lanes_t lanes; /* on the stack: both cores' parts mix at once */
    fill8(lanes.mask5, 31), fill8(lanes.mask6, 63), fill8(lanes.w, m.w), fill8(lanes.ones, 1);
    fill8(lanes.r, m.r), fill8(lanes.g, m.g), fill8(lanes.b, m.b);
    uint32_t saved, tmp;
    if (mode == BLEND_ALPHA) {
        if (swap) KERNEL(ALPHA_CH(L_R), ALPHA_CH(L_G), ALPHA_CH(L_B), SWAP("q0"), SWAP("q7"));
        else KERNEL(ALPHA_CH(L_R), ALPHA_CH(L_G), ALPHA_CH(L_B), "", "");
    } else if (mode == BLEND_SUB) {
        if (swap) KERNEL(SUB_CH(L_R), SUB_CH(L_G), SUB_CH(L_B), SWAP("q0"), SWAP("q7"));
        else KERNEL(SUB_CH(L_R), SUB_CH(L_G), SUB_CH(L_B), "", "");
    } else {
        if (swap) KERNEL(ADD_CH(L_R, q1), ADD_CH(L_G, q4), ADD_CH(L_B, q1), SWAP("q0"), SWAP("q7"));
        else KERNEL(ADD_CH(L_R, q1), ADD_CH(L_G, q4), ADD_CH(L_B, q1), "", "");
    }
    mix_c(p, tail, &m, swap);
}
#else
void span_mix_const(uint16_t *p, int n, uint16_t c, unsigned alpha, int mode, bool swap) {
    span_mix_const_c(p, n, c, alpha, mode, swap);
}
#endif
