/* Lua's memory: small objects cut from chunks, the rest from the heap (lua_mem.h says why). A small object of n bytes
 * takes n rounded up to GRAIN; a freed one is kept on the list for its size and handed to the next object of that size,
 * so memory moves between sizes only when the Lua state is closed and every chunk goes back. The sizes Lua asks for
 * are exact (it passes the old size when it frees or grows a block), so a block needs no header of its own.
 * ponytail: what a size has freed is not given to another size, so a game's footprint is its peaks added up, a tenth or
 * two over what it uses at once; give whole empty chunks back (a count a chunk) if a game that changes its kind of
 * objects between levels needs it. */
#include "lua_mem.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "bp.h"

#define GRAIN 16
#define NSIZES (LUA_MEM_SMALL / GRAIN)
#define CHUNK (32u * 1024u) /* from the heap whole, so 1 MB of objects is thirty-odd blocks, not twelve thousand */
#define CHUNK_HEAD 16       /* the link to the one before, and room to keep the objects' alignment */

typedef struct node {
    struct node *next;
} node;

typedef struct chunk {
    struct chunk *prev;
} chunk;

static node *spare[NSIZES + 1]; /* spare[k]: freed objects of k * GRAIN bytes */
static uint8_t *bump, *bump_end; /* what is left of the newest chunk */
static chunk *newest;
static size_t nchunks;

static inline bool small(size_t n) { return n <= LUA_MEM_SMALL; }
static inline size_t size_class(size_t n) { return (n + GRAIN - 1) / GRAIN; } /* 1..NSIZES for 1..LUA_MEM_SMALL */

static void *small_get(size_t n) {
    const size_t k = size_class(n);
    node *p = spare[k];
    if (p) {
        spare[k] = p->next;
        return p;
    }
    const size_t need = k * GRAIN;
    if ((size_t)(bump_end - bump) < need) { /* (the end of the last chunk, under LUA_MEM_SMALL bytes, is left) */
        chunk *c = hal_realloc_slow(NULL, CHUNK);
        if (!c) return NULL;
        c->prev = newest, newest = c, nchunks++;
        bump = (uint8_t *)(((uintptr_t)c + CHUNK_HEAD + 7) & ~(uintptr_t)7); /* 8 bytes: what Lua's types need */
        bump_end = (uint8_t *)c + CHUNK;
    }
    void *r = bump;
    bump += need;
    return r;
}

static void small_put(void *p, size_t n) {
    node *o = p;
    const size_t k = size_class(n);
    o->next = spare[k], spare[k] = o;
}

void *lua_mem_alloc(void *ud, void *p, size_t osize, size_t nsize) {
    (void)ud;
    if (!p) osize = 0; /* (with no block, Lua's osize is the kind of object it is making) */
    if (!nsize) {
        if (!p) return NULL;
        if (small(osize)) small_put(p, osize);
        else free(p);
        return NULL;
    }
    if (!p) return small(nsize) ? small_get(nsize) : hal_realloc_slow(NULL, nsize);
    if (small(osize) && small(nsize)) {
        if (size_class(osize) == size_class(nsize)) return p; /* the same size, or shrunk within it: where it is */
        void *q = small_get(nsize);
        if (!q) return nsize < osize ? p : NULL; /* (Lua does not expect a block to fail to shrink: it keeps this one) */
        memcpy(q, p, osize < nsize ? osize : nsize);
        small_put(p, osize);
        return q;
    }
    if (!small(osize) && !small(nsize)) return hal_realloc_slow(p, nsize);
    /* from one kind to the other: a new block, the contents moved, the old one let go */
    void *q = small(nsize) ? small_get(nsize) : hal_realloc_slow(NULL, nsize);
    if (!q) return NULL;
    memcpy(q, p, osize < nsize ? osize : nsize);
    if (small(osize)) small_put(p, osize);
    else free(p);
    return q;
}

void lua_mem_reset(void) {
    while (newest) {
        chunk *c = newest;
        newest = c->prev;
        free(c);
    }
    memset(spare, 0, sizeof spare);
    bump = bump_end = NULL;
    nchunks = 0;
}

size_t lua_mem_chunks(void) { return nchunks; }
