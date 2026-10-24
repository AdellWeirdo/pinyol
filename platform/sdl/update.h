/* The desktop app's look for a newer Cirera release: a thread asks GitHub for the latest release once at start, and the app
 * tells the player once for each new version (what the console does not do: its firmware changes only by a file on its card).
 * Off with PINYOL_NO_UPDATE_CHECK=1 in the environment; only the version of the release is read, nothing is sent but the request. */
#pragma once
#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>

#define UPDATE_PAGE "https://github.com/ipaud/pinyol/releases/latest"

/* Is `latest` ("v0.7.0" or "0.7.0") newer than `have`? Up to three numbers, compared in order; text that has none is never newer. */
static inline bool update_newer(const char *have, const char *latest) {
    long a[3] = {0, 0, 0}, b[3] = {0, 0, 0};
    const char *s[2] = {have, latest};
    long *v[2] = {a, b};
    bool any = false;
    for (int k = 0; k < 2; k++) {
        const char *p = s[k];
        for (int i = 0; i < 3; i++) {
            while (*p && !isdigit((unsigned char)*p)) p++;
            if (!*p) break;
            v[k][i] = strtol(p, (char **)&p, 10);
            if (k == 1) any = true;
        }
    }
    if (!any) return false;
    for (int i = 0; i < 3; i++)
        if (b[i] != a[i]) return b[i] > a[i];
    return false;
}

void update_start(const char *have);  /* the thread (nothing in a browser, nothing with PINYOL_NO_UPDATE_CHECK) */
const char *update_found(void);       /* the newer release's tag, once, when the thread has found one the player has not been told of */
void update_told(const char *tag);    /* the player was told: not again for this version */
