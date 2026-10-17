/* The game's reverb: the PlayStation sound chip's, as nocash's psx-spx gives it ("SPU Reverb Formula" and the register
 * values the console's software wrote for each room): two same-side and two cross-side reflections that feed back
 * through a wall, four echoes taken from them, and two all-pass filters, in a ring of memory that moves on by one
 * sample each turn, at AUDIO_HZ. The arithmetic is the chip's: 16-bit samples and volumes, a product divided by 0x8000,
 * every stored value held to 16 bits. A sound reaches it by a send (sfx's reverb), the music and the ambience by
 * theirs; what comes back is mixed in, left and right apart.
 *
 * The registers hold places in the ring in 8-byte units, so 4 samples each, counted from where the ring has got to
 * (so a place is "that many samples ahead", which is how long ago it was written, going round). */
#include <stdlib.h>
#include <string.h>

#include "bp.h"

enum { /* the registers in the order the table lists them, 4 rows of 8 */
    R_dAPF1, R_dAPF2, R_vIIR, R_vCOMB1, R_vCOMB2, R_vCOMB3, R_vCOMB4, R_vWALL,
    R_vAPF1, R_vAPF2, R_mLSAME, R_mRSAME, R_mLCOMB1, R_mRCOMB1, R_mLCOMB2, R_mRCOMB2,
    R_dLSAME, R_dRSAME, R_mLDIFF, R_mRDIFF, R_mLCOMB3, R_mRCOMB3, R_mLCOMB4, R_mRCOMB4,
    R_dLDIFF, R_dRDIFF, R_mLAPF1, R_mRAPF1, R_mLAPF2, R_mRAPF2, R_vLIN, R_vRIN,
    NREGS
};

typedef struct {
    const char *name;
    uint16_t size; /* the ring's size in 16-bit samples would not fit: bytes / 8, as the registers count */
    uint16_t reg[NREGS];
} room;

static const room rooms[] = {
    {"room", 0x26C0 / 8,
     {0x007D, 0x005B, 0x6D80, 0x54B8, 0xBED0, 0x0000, 0x0000, 0xBA80, 0x5800, 0x5300, 0x04D6, 0x0333, 0x03F0, 0x0227,
      0x0374, 0x01EF, 0x0334, 0x01B5, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x01B4, 0x0136,
      0x00B8, 0x005C, 0x8000, 0x8000}},
    {"studio_small", 0x1F40 / 8,
     {0x0033, 0x0025, 0x70F0, 0x4FA8, 0xBCE0, 0x4410, 0xC0F0, 0x9C00, 0x5280, 0x4EC0, 0x03E4, 0x031B, 0x03A4, 0x02AF,
      0x0372, 0x0266, 0x031C, 0x025D, 0x025C, 0x018E, 0x022F, 0x0135, 0x01D2, 0x00B7, 0x018F, 0x00B5, 0x00B4, 0x0080,
      0x004C, 0x0026, 0x8000, 0x8000}},
    {"studio_medium", 0x4840 / 8,
     {0x00B1, 0x007F, 0x70F0, 0x4FA8, 0xBCE0, 0x4510, 0xBEF0, 0xB4C0, 0x5280, 0x4EC0, 0x0904, 0x076B, 0x0824, 0x065F,
      0x07A2, 0x0616, 0x076C, 0x05ED, 0x05EC, 0x042E, 0x050F, 0x0305, 0x0462, 0x02B7, 0x042F, 0x0265, 0x0264, 0x01B2,
      0x0100, 0x0080, 0x8000, 0x8000}},
    {"studio_large", 0x6FE0 / 8,
     {0x00E3, 0x00A9, 0x6F60, 0x4FA8, 0xBCE0, 0x4510, 0xBEF0, 0xA680, 0x5680, 0x52C0, 0x0DFB, 0x0B58, 0x0D09, 0x0A3C,
      0x0BD9, 0x0973, 0x0B59, 0x08DA, 0x08D9, 0x05E9, 0x07EC, 0x04B0, 0x06EF, 0x03D2, 0x05EA, 0x031D, 0x031C, 0x0238,
      0x0154, 0x00AA, 0x8000, 0x8000}},
    {"hall", 0xADE0 / 8,
     {0x01A5, 0x0139, 0x6000, 0x5000, 0x4C00, 0xB800, 0xBC00, 0xC000, 0x6000, 0x5C00, 0x15BA, 0x11BB, 0x14C2, 0x10BD,
      0x11BC, 0x0DC1, 0x11C0, 0x0DC3, 0x0DC0, 0x09C1, 0x0BC4, 0x07C1, 0x0A00, 0x06CD, 0x09C2, 0x05C1, 0x05C0, 0x041A,
      0x0274, 0x013A, 0x8000, 0x8000}},
    {"half_echo", 0x3C00 / 8,
     {0x0017, 0x0013, 0x70F0, 0x4FA8, 0xBCE0, 0x4510, 0xBEF0, 0x8500, 0x5F80, 0x54C0, 0x0371, 0x02AF, 0x02E5, 0x01DF,
      0x02B0, 0x01D7, 0x0358, 0x026A, 0x01D6, 0x011E, 0x012D, 0x00B1, 0x011F, 0x0059, 0x01A0, 0x00E3, 0x0058, 0x0040,
      0x0028, 0x0014, 0x8000, 0x8000}},
    {"space_echo", 0xF6C0 / 8,
     {0x033D, 0x0231, 0x7E00, 0x5000, 0xB400, 0xB000, 0x4C00, 0xB000, 0x6000, 0x5400, 0x1ED6, 0x1A31, 0x1D14, 0x183B,
      0x1BC2, 0x16B2, 0x1A32, 0x15EF, 0x15EE, 0x1055, 0x1334, 0x0F2D, 0x11F6, 0x0C5D, 0x1056, 0x0AE1, 0x0AE0, 0x07A2,
      0x0464, 0x0232, 0x8000, 0x8000}},
    {"delay", 0x18040 / 8,
     {0x0001, 0x0001, 0x7FFF, 0x7FFF, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x1FFF, 0x0FFF, 0x1005, 0x0005,
      0x0000, 0x0000, 0x1005, 0x0005, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x1004, 0x1002,
      0x0004, 0x0002, 0x8000, 0x8000}},
};
#define NROOMS ((int)(sizeof rooms / sizeof rooms[0]))

static int16_t *ring;       /* the room's memory, `n` samples */
static int n, at;           /* its size and where it has got to */
static int cur = -1;        /* the room in use, -1: none */
static int16_t v[NREGS];    /* its registers as signed volumes */
static int32_t off[NREGS];  /* and as places in the ring, in samples */

int reverb_find(const char *name) {
    for (int i = 0; name && i < NROOMS; i++)
        if (!strcmp(rooms[i].name, name)) return i;
    return -1;
}

const char *reverb_name(int i) { return i >= 0 && i < NROOMS ? rooms[i].name : NULL; }
bool reverb_on(void) { return cur >= 0; }
int reverb_current(void) { return cur; }

void reverb_set(int room_index) { /* -1: off. A room fresh from silence */
    free(ring);
    ring = NULL, cur = -1, n = at = 0;
    if (room_index < 0 || room_index >= NROOMS) return;
    const room *r = &rooms[room_index];
    n = r->size * 4;
    if (!(ring = calloc((size_t)n, sizeof *ring))) return n = 0, (void)0;
    for (int i = 0; i < NREGS; i++) v[i] = (int16_t)r->reg[i], off[i] = r->reg[i] * 4 % n;
    cur = room_index;
}

static inline int16_t sat(int x) { return (int16_t)(x < -32768 ? -32768 : x > 32767 ? 32767 : x); }
static inline int16_t *cell(int place) { return &ring[(at + place) % n]; } /* a place, from where the ring has got to */
static inline int16_t *before(int place) { return &ring[(at + place + n - 1) % n]; } /* the sample written a turn before */
static inline int mul(int volume, int sample) { return volume * sample >> 15; }

/* One turn for the input `in` on both sides: the left and right it gives back (16-bit scale, not yet at the wet level) */
static void turn(int in, int *left, int *right) {
    const int lin = mul(v[R_vLIN], in), rin = mul(v[R_vRIN], in);
    /* reflections: the input and what the wall gave back, through the IIR */
    const int pls = *before(off[R_mLSAME]), prs = *before(off[R_mRSAME]), pld = *before(off[R_mLDIFF]), prd = *before(off[R_mRDIFF]);
    *cell(off[R_mLSAME]) = sat(mul(v[R_vIIR], sat(lin + mul(v[R_vWALL], *cell(off[R_dLSAME])) - pls)) + pls);
    *cell(off[R_mRSAME]) = sat(mul(v[R_vIIR], sat(rin + mul(v[R_vWALL], *cell(off[R_dRSAME])) - prs)) + prs);
    *cell(off[R_mLDIFF]) = sat(mul(v[R_vIIR], sat(lin + mul(v[R_vWALL], *cell(off[R_dRDIFF])) - pld)) + pld);
    *cell(off[R_mRDIFF]) = sat(mul(v[R_vIIR], sat(rin + mul(v[R_vWALL], *cell(off[R_dLDIFF])) - prd)) + prd);
    /* four echoes of them */
    int lo = mul(v[R_vCOMB1], *cell(off[R_mLCOMB1])) + mul(v[R_vCOMB2], *cell(off[R_mLCOMB2])) +
             mul(v[R_vCOMB3], *cell(off[R_mLCOMB3])) + mul(v[R_vCOMB4], *cell(off[R_mLCOMB4]));
    int ro = mul(v[R_vCOMB1], *cell(off[R_mRCOMB1])) + mul(v[R_vCOMB2], *cell(off[R_mRCOMB2])) +
             mul(v[R_vCOMB3], *cell(off[R_mRCOMB3])) + mul(v[R_vCOMB4], *cell(off[R_mRCOMB4]));
    lo = sat(lo), ro = sat(ro);
    /* two all-pass filters in a row, each reading what it wrote a delay ago */
    const int dapf1 = v[R_dAPF1] * 4, dapf2 = v[R_dAPF2] * 4;
    for (int k = 0; k < 2; k++) {
        const int dv = k ? dapf2 : dapf1, vol = v[k ? R_vAPF2 : R_vAPF1];
        const int pl = off[k ? R_mLAPF2 : R_mLAPF1], pr = off[k ? R_mRAPF2 : R_mRAPF1];
        int16_t *rl = cell(((pl - dv) % n + n) % n), *rr = cell(((pr - dv) % n + n) % n);
        int ol = *rl, orr = *rr;
        lo = sat(lo - mul(vol, ol)), ro = sat(ro - mul(vol, orr));
        *cell(pl) = (int16_t)lo, *cell(pr) = (int16_t)ro;
        lo = sat(mul(vol, lo) + ol), ro = sat(mul(vol, ro) + orr);
    }
    *left = lo, *right = ro;
    at = (at + 1) % n;
}

/* m samples of the send `in` (the AUDIO_HZ mix's scale) go through the room; what comes back, times wet, is added to
 * left and right. */
void reverb_mix(const float *in, float *left, float *right, int m, float wet) {
    if (cur < 0 || !ring) return;
    for (int i = 0; i < m; i++) {
        const float x = in[i];
        int l, r;
        turn(x < -32768 ? -32768 : x > 32767 ? 32767 : (int)x, &l, &r);
        left[i] += (float)l * wet, right[i] += (float)r * wet;
    }
}
