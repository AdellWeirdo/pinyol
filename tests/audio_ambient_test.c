/* The ambience bus: a bed through a closed lowpass keeps sounding after it is gone (the filter empties by itself), and a
 * bus with nothing in it adds nothing and moves nothing (the mixer leaves it out then). The bed is a WAV made here. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "bp.h"

static int failures, checks;
#define CHECK(c)                                                                             \
    do {                                                                                     \
        checks++;                                                                            \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

static int16_t out[256];

static int peak_of_block(void) { /* one block of the audio thread's, its peak */
    hal_audio_lock();
    audio_mix(out, 256);
    hal_audio_unlock();
    int p = 0;
    for (int i = 0; i < 256; i++) p = abs(out[i]) > p ? abs(out[i]) : p;
    return p;
}

static void wav(const char *path, int n) { /* PCM16 mono AUDIO_HZ: a steady level, which a shut lowpass climbs to slowly */
    FILE *f = fopen(path, "wb");
    uint32_t hz = AUDIO_HZ, bytes = (uint32_t)n * 2, riff = 36 + bytes, fmt = 16, rate2 = hz * 2;
    uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
    fwrite("RIFF", 1, 4, f), fwrite(&riff, 4, 1, f), fwrite("WAVEfmt ", 1, 8, f), fwrite(&fmt, 4, 1, f);
    fwrite(&pcm, 2, 1, f), fwrite(&ch, 2, 1, f), fwrite(&hz, 4, 1, f), fwrite(&rate2, 4, 1, f);
    fwrite(&align, 2, 1, f), fwrite(&bits, 2, 1, f), fwrite("data", 1, 4, f), fwrite(&bytes, 4, 1, f);
    for (int i = 0; i < n; i++) {
        int16_t v = 12000;
        fwrite(&v, 2, 1, f);
    }
    fclose(f);
}

int main(void) {
    char dir[] = "/tmp/pinyol_ambient_XXXXXX", path[256];
    if (!mkdtemp(dir)) return 1;
    snprintf(path, sizeof path, "%s/audio", dir), mkdir(path, 0700);
    snprintf(path, sizeof path, "%s/audio/bed.wav", dir), wav(path, AUDIO_HZ);
    snprintf(G.game_dir, sizeof G.game_dir, "%s", dir);
    audio_reset();

    for (int i = 0; i < 20; i++) CHECK(peak_of_block() == 0); /* nothing playing: silence, and it stays so */

    audio_bus(1, 1, 10, 0); /* the bed's lowpass nearly shut: it fills slowly and takes a block or two to empty */
    audio_ambient("bed", 0);
    int heard = 0;
    for (int i = 0; i < 30; i++) { int p = peak_of_block(); heard = p > heard ? p : heard; }
    CHECK(heard > 500);

    audio_ambient(NULL, 0); /* the bed goes; the filter still holds what it was singing, and sings it out */
    for (int i = 0; i < 6; i++) { /* through the block the stream closes in: a smooth line, never cut to nothing */
        int last = out[255];
        peak_of_block();
        CHECK(abs(out[0] - last) <= 200); /* it falls some 35 a sample; cut, it would fall by thousands */
    }

    for (int i = 0; i < 4000; i++) peak_of_block(); /* a long time on: it has emptied, and nothing is heard */
    CHECK(peak_of_block() == 0);
    audio_bus(1, 1, 0, 0); /* the lowpass opened again, with the bus empty: still nothing */
    for (int i = 0; i < 5; i++) CHECK(peak_of_block() == 0);
    audio_ambient("bed", 0); /* and a bed started now plays at once, the skipped bus not having stood in its way */
    int again = 0;
    for (int i = 0; i < 10; i++) { int p = peak_of_block(); again = p > again ? p : again; }
    CHECK(again > 5000);

    printf("audio_ambient: %d checks, %d failures\n", checks, failures);
    return failures != 0;
}
