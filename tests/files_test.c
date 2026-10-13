/* The game's folders listed once (game_has, src/content.c): a file there, one not there, any case, a new load. */
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include "bp.h"

static int failures, checks;
#define CHECK(c)                                                                  \
    do {                                                                          \
        checks++;                                                                 \
        if (!(c)) failures++, fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
    } while (0)

static void touch(const char *path) {
    FILE *f = fopen(path, "wb");
    if (f) fclose(f);
}

int main(void) {
    const char *dir = "files_test_game"; /* (in the build folder: ctest runs there) */
    char p[300];
    mkdir(dir, 0755);
    snprintf(p, sizeof p, "%s/assets", dir);
    mkdir(p, 0755);
    snprintf(p, sizeof p, "%s/assets/A.meta.json", dir);
    touch(p);
    snprintf(p, sizeof p, "%s/assets/B.meta.json", dir);
    remove(p); /* (a run before made it) */
    snprintf(G.game_dir, sizeof G.game_dir, "%s", dir);

    CHECK(game_has("assets/A.meta.json"));
    CHECK(game_has("assets/a.META.json")); /* the card's FAT finds any case */
    CHECK(!game_has("assets/B.meta.json"));
    touch(p);
    CHECK(!game_has("assets/B.meta.json")); /* listed once: a file made since is not seen... */
    content_free();
    CHECK(game_has("assets/B.meta.json"));  /* ...until the game is loaded again */
    CHECK(game_has("nothere/x.wav"));       /* a folder that cannot be listed: every file is tried */
    CHECK(game_has("game.json"));           /* the game's own folder is not listed: tried */

    printf("%d checks, %d failures\n", checks, failures);
    return failures != 0;
}
