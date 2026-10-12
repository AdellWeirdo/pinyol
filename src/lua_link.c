/* link.*: messages between consoles playing the same game near each other (link.c). The radio comes on the first
 * time the game uses one of these; where there is none, the game plays alone (no consoles, nothing sent).
 *
 *   link.send(value [, to]) -> true, or false when this console has used up its share of the air for now
 *   link.recv() -> from, value of the oldest message waiting; nil when none
 *   link.peers() -> {id, ...}: the consoles playing this game nearby, smallest id first
 *   link.id() -> this console's id (0 without a radio)
 * A value is a number, string, boolean or a table of them (as store), up to LINK_PAYLOAD bytes as JSON. Messages
 * can be lost: a game sends its state often rather than a change once. */
#include "lua_api.h"

static bool ready(void) {
    if (link_active()) return true;
    const char *id = jstr(G.game, "id");
    return link_start(id && *id ? id : G.game_dir);
}

static int l_send(lua_State *L) {
    luaL_checkany(L, 1);
    lua_Integer to = luaL_optinteger(L, 2, 0);
    int count = 0;
    cJSON *v = json_from_lua(L, 1, 0, "link.send", &count);
    if (!v) return lua_error(L);
    char *txt = cJSON_PrintUnformatted(v);
    cJSON_Delete(v);
    if (!txt) return luaL_error(L, "link.send: out of memory");
    int r = ready() ? link_send(txt, (int)strlen(txt), (uint32_t)to) : LINK_OFF;
    cJSON_free(txt);
    if (r == LINK_TOO_BIG) return luaL_error(L, "link.send: a message is %d bytes at most, as JSON", LINK_PAYLOAD);
    lua_pushboolean(L, r == LINK_SENT);
    return 1;
}

static int l_recv(lua_State *L) {
    link_msg m;
    while (ready() && link_recv(&m)) {
        cJSON *v = cJSON_ParseWithLength(m.data, m.len); /* from another console: anything may come */
        if (!v) continue;
        lua_pushinteger(L, (lua_Integer)m.from);
        json_to_lua(L, v, 0);
        cJSON_Delete(v);
        return 2;
    }
    return 0;
}

static int l_peers(lua_State *L) {
    uint32_t ids[LINK_PEERS];
    int n = ready() ? link_peers(ids, LINK_PEERS) : 0;
    for (int i = 1; i < n; i++) /* smallest first: every console sees the same order */
        for (int j = i; j > 0 && ids[j - 1] > ids[j]; j--) {
            uint32_t t = ids[j];
            ids[j] = ids[j - 1], ids[j - 1] = t;
        }
    lua_createtable(L, n, 0);
    for (int i = 0; i < n; i++) lua_pushinteger(L, (lua_Integer)ids[i]), lua_rawseti(L, -2, i + 1);
    return 1;
}

static int l_id(lua_State *L) {
    lua_pushinteger(L, ready() ? (lua_Integer)link_id() : 0);
    return 1;
}

void link_register(lua_State *L) {
    static const luaL_Reg F[] = {{"send", l_send}, {"recv", l_recv}, {"peers", l_peers}, {"id", l_id}, {NULL, NULL}};
    luaL_newlib(L, F);
    lua_setglobal(L, "link");
}
