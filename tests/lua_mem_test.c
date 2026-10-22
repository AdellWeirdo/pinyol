/* Lua's memory (src/lua_mem.c): thousands of blocks made, grown, shrunk and freed at random across the small/big
 * border, each filled with a pattern of its own and checked before it changes or goes, so a block that overlaps another
 * or loses its contents fails; every block 8-aligned; ten thousand small objects cut from a few chunks, not as many
 * blocks; and every chunk back to the heap at the reset. Run under the sanitizers like the rest. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua_mem.h"

#define LIVE 3000
#define OPS 400000

static struct {
    uint8_t *p;
    size_t n;
    uint32_t seed;
} blk[LIVE];

static uint32_t rng = 12345;
static uint32_t next(void) { return rng = rng * 1664525u + 1013904223u; }

static uint8_t pat(uint32_t seed, size_t i) { return (uint8_t)((seed >> 8) + i * 31u + (i >> 3)); }
static void fill(int k, size_t from) {
    for (size_t i = from; i < blk[k].n; i++) blk[k].p[i] = pat(blk[k].seed, i);
}
static int check(int k, size_t upto) { /* the first upto bytes are still its pattern */
    for (size_t i = 0; i < upto && i < blk[k].n; i++)
        if (blk[k].p[i] != pat(blk[k].seed, i)) return 0;
    return 1;
}

static size_t any_size(void) { /* mostly small, as Lua's objects are, a few across the border and a few big */
    uint32_t r = next() % 100;
    if (r < 80) return 1 + next() % LUA_MEM_SMALL;
    if (r < 92) return LUA_MEM_SMALL - 8 + next() % 24; /* on the border */
    return 1 + next() % 6000;
}

#define CHECK(cond, what)                                                   \
    do {                                                                    \
        if (!(cond)) {                                                      \
            printf("lua_mem_test: FAIL %s (op %d)\n", what, op);            \
            return 1;                                                       \
        }                                                                   \
    } while (0)

int main(void) {
    int op = 0;
    for (; op < OPS; op++) {
        int k = (int)(next() % LIVE);
        size_t n = blk[k].n;
        switch (next() % 4) {
        case 0: /* free */
            if (blk[k].p) {
                CHECK(check(k, n), "contents before free");
                lua_mem_alloc(NULL, blk[k].p, n, 0);
                blk[k].p = NULL, blk[k].n = 0;
            }
            break;
        case 1: /* grow or shrink */
            if (blk[k].p) {
                size_t m = any_size();
                CHECK(check(k, n), "contents before resize");
                uint8_t *q = lua_mem_alloc(NULL, blk[k].p, n, m);
                CHECK(q != NULL, "resize failed");
                CHECK(((uintptr_t)q & 7) == 0, "alignment after resize");
                blk[k].p = q, blk[k].n = m;
                CHECK(check(k, n < m ? n : m), "contents kept by resize");
                fill(k, n < m ? n : 0); /* the new part, or all of it when it shrank (same seed: only the head is kept) */
            }
            break;
        default: /* make */
            if (!blk[k].p) {
                blk[k].n = any_size(), blk[k].seed = next();
                blk[k].p = lua_mem_alloc(NULL, NULL, 7 /* (Lua's kind of object, not a size) */, blk[k].n);
                CHECK(blk[k].p != NULL, "alloc failed");
                CHECK(((uintptr_t)blk[k].p & 7) == 0, "alignment");
                fill(k, 0);
            }
        }
    }
    for (int k = 0; k < LIVE; k++) {
        if (!blk[k].p) continue;
        CHECK(check(k, blk[k].n), "contents at the end");
        lua_mem_alloc(NULL, blk[k].p, blk[k].n, 0);
    }
    lua_mem_reset();
    CHECK(lua_mem_chunks() == 0, "chunks after the reset");

    /* ten thousand small objects: a few chunks, and when freed all of them come back for the next ones */
    static void *many[10000];
    for (int i = 0; i < 10000; i++) {
        many[i] = lua_mem_alloc(NULL, NULL, 5, 48);
        CHECK(many[i] != NULL, "small alloc");
        memset(many[i], 0xAB, 48);
    }
    size_t chunks = lua_mem_chunks();
    CHECK(chunks >= 14 && chunks <= 18, "ten thousand 48-byte objects in some 15 chunks of 32 KB");
    for (int i = 0; i < 10000; i++) lua_mem_alloc(NULL, many[i], 48, 0);
    for (int i = 0; i < 10000; i++) CHECK((many[i] = lua_mem_alloc(NULL, NULL, 5, 40)) != NULL, "reused");
    CHECK(lua_mem_chunks() == chunks, "freed objects are used again, no new chunk");
    for (int i = 0; i < 10000; i++) lua_mem_alloc(NULL, many[i], 40, 0);
    lua_mem_reset();
    CHECK(lua_mem_chunks() == 0, "chunks after the second reset");
    printf("lua_mem_test: OK (%d operations)\n", OPS);
    return 0;
}
