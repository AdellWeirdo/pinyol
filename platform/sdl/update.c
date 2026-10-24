#include "update.h"

#include <SDL.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#define POPEN _popen
#define PCLOSE _pclose
#else
#define POPEN popen
#define PCLOSE pclose
#endif

static char have_tag[32], found_tag[32];
static SDL_atomic_t ready;

static void seen_path(char *path, size_t n) {
    char *pref = SDL_GetPrefPath("pinyol", "Cirera");
    snprintf(path, n, "%s%s", pref ? pref : "", "update_seen.txt");
    SDL_free(pref);
}

static int ask(void *unused) {
    (void)unused;
    FILE *p = POPEN("curl -s -m 6 -H \"User-Agent: Cirera\" https://api.github.com/repos/ipaud/pinyol/releases/latest", "r");
    if (!p) return 0;
    char buf[65536];
    size_t n = fread(buf, 1, sizeof buf - 1, p);
    PCLOSE(p);
    buf[n] = 0;
    const char *t = strstr(buf, "\"tag_name\"");
    if (!t || !(t = strchr(t + 10, ':')) || !(t = strchr(t, '"'))) return 0;
    t++;
    size_t len = strcspn(t, "\"");
    if (len == 0 || len >= sizeof found_tag || !update_newer(have_tag, memcpy(found_tag, t, len) ? (found_tag[len] = 0, found_tag) : "")) {
        found_tag[0] = 0;
        return 0;
    }
    char path[1200], told[32] = "";
    seen_path(path, sizeof path);
    FILE *f = fopen(path, "r");
    if (f) fgets(told, sizeof told, f), fclose(f);
    told[strcspn(told, "\r\n")] = 0;
    if (strcmp(told, found_tag)) SDL_AtomicSet(&ready, 1);
    return 0;
}

void update_start(const char *have) {
#ifndef __EMSCRIPTEN__
    const char *off = getenv("PINYOL_NO_UPDATE_CHECK");
    if (!have || !*have || (off && *off && *off != '0')) return;
    snprintf(have_tag, sizeof have_tag, "%s", have);
    SDL_Thread *th = SDL_CreateThread(ask, "update", NULL);
    if (th) SDL_DetachThread(th);
#else
    (void)have;
#endif
}

const char *update_found(void) { return SDL_AtomicGet(&ready) ? found_tag : NULL; }

void update_told(const char *tag) {
    SDL_AtomicSet(&ready, 0);
    char path[1200];
    seen_path(path, sizeof path);
    FILE *f = fopen(path, "w");
    if (f) fputs(tag, f), fclose(f);
}
