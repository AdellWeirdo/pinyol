/* A play recorded as a test script (record.h). Ticks with the same input become one line, `in N SPEC [X Y ...]`:
 * N ticks of the buttons SPEC (names joined by +, or - for none) with the fingers at those points. */
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "record.h"

static FILE *f;
static hal_input last;
static int run;      /* ticks with `last` as input, not written yet */
static long ticks;   /* recorded so far */

static bool same(const hal_input *a, const hal_input *b) {
    if (a->held != b->held || a->touch != b->touch) return false;
    const int na = a->points ? a->points : a->touch, nb = b->points ? b->points : b->touch;
    if (na != nb) return false;
    for (int i = 0; i < na; i++) {
        const int ax = i || a->points ? a->x[i] : a->px, ay = i || a->points ? a->y[i] : a->py;
        const int bx = i || b->points ? b->x[i] : b->px, by = i || b->points ? b->y[i] : b->py;
        if (ax != bx || ay != by) return false;
    }
    return true;
}

static void flush(void) {
    if (!f || !run) return;
    fprintf(f, "in %d ", run);
    static const struct { uint16_t bit; const char *name; } B[] = {{ACT_UP, "UP"}, {ACT_DOWN, "DOWN"}, {ACT_LEFT, "LEFT"},
        {ACT_RIGHT, "RIGHT"}, {ACT_OK, "A"}, {ACT_BACK, "B"}, {ACT_NEXT, "C"}, {ACT_PAUSE, "START"}, {ACT_INV, "MENU"}};
    bool any = false;
    for (size_t i = 0; i < sizeof B / sizeof B[0]; i++)
        if (last.held & B[i].bit) fprintf(f, "%s%s", any ? "+" : "", B[i].name), any = true;
    if (!any) fputc('-', f);
    const int n = last.points ? last.points : last.touch;
    for (int i = 0; i < n && i < HAL_POINTS; i++)
        fprintf(f, " %d %d", i || last.points ? last.x[i] : last.px, i || last.points ? last.y[i] : last.py);
    fputc('\n', f);
    run = 0;
}

bool record_start(const char *path, const char *game_id) {
    record_stop();
    f = fopen(path, "w");
    if (!f) return false;
    char when[32] = "";
    time_t now = time(NULL);
    struct tm *tm = gmtime(&now);
    if (tm) strftime(when, sizeof when, "%Y-%m-%d %H:%M UTC", tm);
    fprintf(f, "# %s played on %s, recorded by pinyol (play it: pinyol_headless --game DIR --fresh --script THIS)\n", game_id ? game_id : "a game", when);
    fputs("new\n", f);
    memset(&last, 0, sizeof last);
    run = 0, ticks = 0;
    return true;
}

bool record_on(void) { return f != NULL; }

void record_tick(const hal_input *in) {
    if (!f) return;
    hal_input now = *in;
    now.held &= ~ACT_QUIT;
    if (ticks++ == 0 && !now.held && !now.touch && !now.points) return; /* the headless player's `new` takes the first, idle, tick */
    if (run && !same(&now, &last)) flush();
    last = now;
    run++;
}

void record_stop(void) {
    if (!f) return;
    flush();
    fputs("expect_ok\n", f);
    fclose(f);
    f = NULL;
}
