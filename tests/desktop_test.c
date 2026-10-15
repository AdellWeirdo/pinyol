/* platform/sdl/desktop.c's install, for tests/desktop_test.py: each .zip given installed into GAMES, a line each with
 * the name it got, or "-" if it was refused.   desktop_test GAMES ZIP...   */
#include <stdio.h>

#include "desktop.h"

void hal_log(const char *fmt, ...) { (void)fmt; }

int main(int argc, char **argv) {
    for (int i = 2; i < argc; i++) {
        char name[128];
        printf("%s\n", desktop_install(argv[i], argv[1], name, sizeof name) ? name : "-");
    }
    return 0;
}
