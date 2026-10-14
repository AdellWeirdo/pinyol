/* Consoles playing the same game near each other, sending each other small messages (pinyol@2's link.*).
 * The platform carries packets (hal_link_*); this file gives them a shape, keeps the list of consoles heard, a queue
 * of what came in for the game, and each console's fair share of the air.
 *
 * A packet: "NP2L", version, kind (1 hello, 2 message), the game's hash, from, to (0: everyone), sequence, then the
 * message as JSON. Only consoles running the same game (same id in game.json) hear each other's messages. */
#include <stdio.h>
#include <string.h>

#include "bp.h"

#define HEAD 20
#define HELLO_TICKS 60 /* a console says it is there once a second */
#define GONE_TICKS 180 /* and is forgotten after three seconds of silence */
#define RATE 20        /* messages a second a console may send */

static bool on, failed;
static uint32_t game_hash, me, now;
static uint16_t seq;
static int tokens; /* in sixtieths of a message: RATE a second, at most RATE banked */
static struct { uint32_t id, heard; } peer[LINK_PEERS];
static int npeers;
static link_msg queue[LINK_QUEUE];
static int qhead, qlen;
static char sent[8][LINK_PAYLOAD + 1]; /* the last ones this console sent, for tests */
static uint32_t recent[32]; /* from and sequence of the last packets heard: copies are dropped */
static int nrecent;
static int nsent;

static uint32_t hash(const char *s) { /* FNV-1a */
    uint32_t h = 2166136261u;
    for (; *s; s++) h = (h ^ (uint8_t)*s) * 16777619u;
    return h ? h : 1;
}

static void put32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 24), p[1] = (uint8_t)(v >> 16), p[2] = (uint8_t)(v >> 8), p[3] = (uint8_t)v; }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }

static void heard(uint32_t id) {
    for (int i = 0; i < npeers; i++)
        if (peer[i].id == id) {
            peer[i].heard = now;
            return;
        }
    if (npeers < LINK_PEERS) peer[npeers].id = id, peer[npeers++].heard = now;
}

static void enqueue(uint32_t from, const char *data, int len) {
    if (qlen == LINK_QUEUE) qhead = (qhead + 1) % LINK_QUEUE, qlen--; /* full: the oldest goes */
    link_msg *m = &queue[(qhead + qlen++) % LINK_QUEUE];
    m->from = from, m->len = (uint16_t)len;
    memcpy(m->data, data, (size_t)len);
    m->data[len] = 0;
}

static bool packet(int kind, uint32_t to, const char *data, int len) {
    uint8_t p[HAL_LINK_MAX];
    memcpy(p, "NP2L", 4);
    p[4] = 1, p[5] = (uint8_t)kind;
    put32(p + 6, game_hash), put32(p + 10, me), put32(p + 14, to);
    p[18] = (uint8_t)(seq >> 8), p[19] = (uint8_t)seq, seq++;
    memcpy(p + HEAD, data, (size_t)len);
    return hal_link_send(p, HEAD + len);
}

bool link_start(const char *game_id) {
    if (on) return true;
    if (failed) return false;
    if (!hal_link_open()) {
        failed = true; /* no radio here: the game plays alone, without asking again every tick */
        hal_log("link: no radio on this platform");
        return false;
    }
    on = true, game_hash = hash(game_id), me = hal_link_id() & 0x7FFFFFFF, npeers = qhead = qlen = 0, tokens = RATE * 60;
    if (!me) me = 1; /* ids fit a game's 32-bit integers, and 0 means everyone */
    nsent = 0;
    hal_log("link: on, console %08x, game %s", (unsigned)me, game_id);
    packet(1, 0, "", 0);
    return true;
}

void link_stop(void) {
    if (on) hal_link_close();
    on = failed = false, npeers = qhead = qlen = 0;
}

bool link_active(void) { return on; }
uint32_t link_id(void) { return on ? me : 0; }

void link_tick(uint32_t ticks) {
    if (!on) return;
    now = ticks;
    tokens = tokens + RATE > RATE * 60 ? RATE * 60 : tokens + RATE;
    if (ticks % HELLO_TICKS == 0) packet(1, 0, "", 0);
    uint8_t p[HAL_LINK_MAX + 1];
    for (int n, budget = 64; budget-- > 0 && (n = hal_link_recv(p, HAL_LINK_MAX)) > 0;) {
        if (n < HEAD || memcmp(p, "NP2L", 4) || p[4] != 1 || get32(p + 6) != game_hash) continue; /* not ours */
        uint32_t from = get32(p + 10), to = get32(p + 14), tag = from * 65599u ^ (uint32_t)(p[18] << 8 | p[19]);
        if (from == me || from == 0) continue;
        bool copy = false;
        for (int i = 0; i < 32 && !copy; i++) copy = recent[i] == tag;
        if (copy) continue; /* the same packet by another way (a desktop's two interfaces) */
        recent[nrecent++ % 32] = tag;
        heard(from);
        if (p[5] == 2 && (to == 0 || to == me) && n - HEAD <= LINK_PAYLOAD) enqueue(from, (const char *)p + HEAD, n - HEAD);
    }
    for (int i = 0; i < npeers;) /* the ones not heard for a while have gone */
        if (now - peer[i].heard > GONE_TICKS) peer[i] = peer[--npeers];
        else i++;
}

int link_send(const char *data, int len, uint32_t to) {
    if (!on) return LINK_OFF;
    if (len > LINK_PAYLOAD) return LINK_TOO_BIG;
    if (tokens < 60) return LINK_BUSY;
    tokens -= 60;
    char *keep = sent[nsent++ % 8];
    memcpy(keep, data, (size_t)len);
    keep[len] = 0;
    return packet(2, to, data, len) ? LINK_SENT : LINK_BUSY;
}

bool link_recv(link_msg *m) {
    if (!qlen) return false;
    *m = queue[qhead];
    qhead = (qhead + 1) % LINK_QUEUE, qlen--;
    return true;
}

int link_peers(uint32_t *ids, int max) {
    int n = 0;
    for (int i = 0; i < npeers && n < max; i++) ids[n++] = peer[i].id;
    return n;
}

void link_inject(uint32_t from, const char *json) { /* tests: as if console `from` had sent it */
    if (!on || !from || from == me) return;
    heard(from);
    int len = (int)strlen(json);
    if (len <= LINK_PAYLOAD) enqueue(from, json, len);
}

bool link_sent_lately(const char *text) { /* tests: one of the last 8 messages sent contains it */
    for (int i = 0; i < 8 && i < nsent; i++)
        if (strstr(sent[(nsent - 1 - i) % 8], text)) return true;
    return false;
}
