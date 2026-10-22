#pragma once
#include <stddef.h>

/* Lua's memory (lua_Alloc). A game makes tens of thousands of small objects (tables, strings, closures) that live and
 * die with the garbage collector; each handed to the heap on its own, they scatter through the console's PSRAM and
 * split it, so that with 1.5 MB free no block of 600 KB is left for a picture (measured on the board: 12 000 blocks
 * allocated, the largest free one 320 KB). So the small ones (up to LUA_MEM_SMALL bytes) are cut from chunks taken from
 * the heap whole, a freed one waits on the list of its size for the next of that size, and the chunks go back to the
 * heap when the Lua state is closed. Bigger ones (the arrays of a big table, a long string) stay with the heap.
 * The quota and the count of memory used are the caller's (lua_game.c). */
#define LUA_MEM_SMALL 256

void *lua_mem_alloc(void *ud, void *p, size_t osize, size_t nsize);
void lua_mem_reset(void); /* every chunk back to the heap: the state is closed and nothing of it is left */
size_t lua_mem_chunks(void); /* the chunks held now (the test, the meter) */
