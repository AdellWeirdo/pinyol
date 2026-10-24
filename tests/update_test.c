/* The desktop app's version comparison (platform/sdl/update.h): which release counts as newer. */
#include <stdio.h>

#include "update.h"

static int fails;
#define CHECK(c) do { if (!(c)) fails++, fprintf(stderr, "update_test: failed: %s (line %d)\n", #c, __LINE__); } while (0)

int main(void) {
    CHECK(update_newer("0.6.0", "v0.7.0"));
    CHECK(update_newer("v0.6.0", "v0.6.1"));
    CHECK(update_newer("0.6.9", "1.0.0"));
    CHECK(!update_newer("0.6.0", "v0.6.0"));
    CHECK(!update_newer("0.7.0", "v0.6.0"));
    CHECK(update_newer("0.9.0", "0.10.0")); /* numbers, not text */
    CHECK(!update_newer("0.6.0", ""));
    CHECK(!update_newer("0.6.0", "nightly"));
    CHECK(update_newer("0.6", "v0.6.1"));
    if (!fails) puts("update_test: ok");
    return fails ? 1 : 0;
}
