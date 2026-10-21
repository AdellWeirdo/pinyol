/* The crash screen's QR code (third_party/qrcodegen, as sysmenu.c uses it): a short text and a long one encode within
 * version 10, their size grows with the text, and the finder patterns sit where a phone looks for them. */
#include <stdio.h>
#include <string.h>

#include "qrcodegen.h"

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "qr_test: %s (line %d)\n", #c, __LINE__); return 1; } } while (0)

static int finder_ok(const uint8_t *qr, int x0, int y0) { /* a 7 x 7 finder: dark ring, light ring, dark 3 x 3 centre */
    for (int y = 0; y < 7; y++)
        for (int x = 0; x < 7; x++) {
            const int ring = (x == 0 || x == 6 || y == 0 || y == 6) ? 1 : (x == 1 || x == 5 || y == 1 || y == 5) ? 0 : 1;
            if (qrcodegen_getModule(qr, x0 + x, y0 + y) != (ring == 1)) return 0;
        }
    return 1;
}

int main(void) {
    uint8_t temp[qrcodegen_BUFFER_LEN_FOR_VERSION(10)], qr[qrcodegen_BUFFER_LEN_FOR_VERSION(10)];
    CHECK(qrcodegen_encodeText("pinyol prueba: main.lua:12: boom", temp, qr, qrcodegen_Ecc_LOW, 1, 10, qrcodegen_Mask_AUTO, true));
    const int small = qrcodegen_getSize(qr);
    CHECK(small >= 21 && small <= 57 && small % 4 == 1);
    CHECK(finder_ok(qr, 0, 0) && finder_ok(qr, small - 7, 0) && finder_ok(qr, 0, small - 7));
    char text[320] = "pinyol trece: ";
    for (int i = 0; i < 240; i++) text[14 + i] = (char)('a' + i % 26);
    text[254] = 0;
    CHECK(qrcodegen_encodeText(text, temp, qr, qrcodegen_Ecc_LOW, 1, 10, qrcodegen_Mask_AUTO, true));
    const int big = qrcodegen_getSize(qr);
    CHECK(big > small && big <= 57);
    CHECK(finder_ok(qr, 0, 0) && finder_ok(qr, big - 7, 0) && finder_ok(qr, 0, big - 7));
    for (int i = 0; i < 300; i++) text[14 + i] = 'x';
    text[314] = 0; /* 300 bytes: more than version 10 holds at the lowest correction: refused, not overflowed */
    CHECK(!qrcodegen_encodeText(text, temp, qr, qrcodegen_Ecc_LOW, 1, 10, qrcodegen_Mask_AUTO, true));
    printf("qr: ok (%d and %d modules a side)\n", small, big);
    return 0;
}
