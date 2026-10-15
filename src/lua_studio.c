/* The studio (docs/lua.md, "The studio"): a step sequencer in the audio thread, every step on its sample.
 *
 *   studio.tempo(bpm [, swing]);  studio.length(steps);  studio.track(i, {sound, gain, pitch, choke}) -> loaded?
 *   studio.steps(i, {v, v, ...});  studio.play([step]);  studio.stop();  studio.playing()
 *   studio.pos() -> step, fraction (what the player hears now; nil when stopped);  studio.hit(i [, velocity])
 *   studio.synth(i, {wave, cutoff, res, env, decay, accent, glide, drive, volume, tune})
 *   studio.notes(i, {note, {note, accent = true, slide = true}, 0, ...});  studio.note(i [, note [, accent]])
 *   studio.fx({delay, feedback, tone, reverb = "plate" | "gba", size, damp, lofi});  sends: track's delay, reverb */
#include <stdlib.h>
#include <string.h>

#include "lua_api.h"
#include "studio_synth.h"

static void sends_from(lua_State *L, int i, int t) { /* a track's {delay, reverb}: how much it sends to each */
    studio_sends(i, opt_float(L, t, "delay", -1, -1, 1), opt_float(L, t, "reverb", -1, -1, 1));
}

static int track_arg(lua_State *L, int a) {
    lua_Integer i = luaL_checkinteger(L, a);
    if (i < 1 || i > STUDIO_TRACKS)
        return luaL_error(L, "studio: track %d does not exist (1 to %d)", (int)i, STUDIO_TRACKS);
    return (int)i - 1;
}

static int l_tempo(lua_State *L) { /* studio.tempo(bpm [, swing]): 30..300 BPM; swing 50 (straight) to 75 % */
    studio_tempo(fin(luaL_checknumber(L, 1)), lua_isnoneornil(L, 2) ? -1 : fin(luaL_checknumber(L, 2)));
    return 0;
}

static int l_length(lua_State *L) {
    lua_Integer n = luaL_checkinteger(L, 1);
    if (n < 1 || n > STUDIO_STEPS) return luaL_error(L, "studio.length: %d steps (1 to %d)", (int)n, STUDIO_STEPS);
    studio_length((int)n);
    return 0;
}

/* studio.track(i, {sound, gain, pitch, choke}): what is left out stays as it was. True if its sound is loaded. */
static int l_track(lua_State *L) {
    int i = track_arg(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_getfield(L, 2, "sound");
    const char *sound = lua_isnil(L, -1) ? NULL : luaL_checkstring(L, -1);
    if (sound && (!safe_name(sound) || strlen(sound) >= 32)) return luaL_error(L, "studio.track: \"%s\" is not a sound name", sound);
    float gain = opt_float(L, 2, "gain", -1, -1, 1), pitch = opt_float(L, 2, "pitch", -1, -1, 16);
    lua_getfield(L, 2, "choke");
    int choke = lua_isnil(L, -1) ? -1 : (int)luaL_checkinteger(L, -1);
    if (choke < -1 || choke > 15) return luaL_error(L, "studio.track: choke group %d (0, none, to 15)", choke);
    sends_from(L, i, 2);
    lua_pushboolean(L, studio_track(i, sound, gain, pitch, choke));
    return 1;
}

/* studio.steps(i, {v, v, ...}): each step's velocity, 0 (silent) to 1; true and false are 1 and 0. */
static int l_steps(lua_State *L) {
    int i = track_arg(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    float vel[STUDIO_STEPS];
    int n = (int)luaL_len(L, 2);
    if (n > STUDIO_STEPS) return luaL_error(L, "studio.steps: %d steps (%d at most)", n, STUDIO_STEPS);
    for (int s = 0; s < n; s++) {
        lua_rawgeti(L, 2, s + 1);
        vel[s] = lua_isboolean(L, -1) ? (float)lua_toboolean(L, -1) : lua_isnil(L, -1) ? 0 : fin(luaL_checknumber(L, -1));
        lua_pop(L, 1);
    }
    studio_steps(i, vel, n);
    return 0;
}

static int l_play(lua_State *L) {
    studio_play((int)luaL_optinteger(L, 1, 1) - 1);
    return 0;
}

static int l_stop(lua_State *L) {
    (void)L;
    studio_stop();
    return 0;
}

static int l_playing(lua_State *L) {
    lua_pushboolean(L, studio_playing());
    return 1;
}

static int l_pos(lua_State *L) { /* studio.pos() -> step (1 = the first), fraction into it; nil before one is heard */
    int step;
    float frac;
    if (!studio_pos(&step, &frac)) return 0;
    lua_pushinteger(L, step + 1);
    lua_pushnumber(L, frac);
    return 2;
}

static int l_hit(lua_State *L) {
    studio_hit(track_arg(L, 1), lua_isnoneornil(L, 2) ? 1 : fin(luaL_checknumber(L, 2)));
    return 0;
}

static const char *const SV_WAVES[] = {"saw", "square", NULL};

/* studio.synth(i, {wave, cutoff, res, env, decay, accent, glide, drive, volume, tune}): track i plays notes on a
 * synth voice; what is left out stays as it was (or as the defaults, the first time). */
static int l_synth(lua_State *L) {
    int i = track_arg(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    sv_patch p;
    if (!studio_synth_get(i, &p)) sv_defaults(&p);
    lua_getfield(L, 2, "wave");
    if (!lua_isnil(L, -1)) p.wave = luaL_checkoption(L, -1, NULL, SV_WAVES);
    lua_pop(L, 1);
    p.cutoff = opt_float(L, 2, "cutoff", p.cutoff, 0, 1);
    p.res = opt_float(L, 2, "res", p.res, 0, 1);
    p.env = opt_float(L, 2, "env", p.env, 0, 1);
    p.decay = opt_float(L, 2, "decay", p.decay, 0.01f, 4);
    p.accent = opt_float(L, 2, "accent", p.accent, 0, 1);
    p.glide = opt_float(L, 2, "glide", p.glide, 0.002f, 2);
    p.drive = opt_float(L, 2, "drive", p.drive, 0, 1);
    p.volume = opt_float(L, 2, "volume", p.volume, 0, 1);
    p.tune = opt_float(L, 2, "tune", p.tune, -48, 48);
    studio_synth(i, &p);
    sends_from(L, i, 2);
    return 0;
}

/* A note as MIDI (60 is C4), a name ("C2", "F#1", "Bb3") or 0, nil or false for a rest. */
static int midi_of(lua_State *L, int idx) {
    if (lua_isnoneornil(L, idx) || (lua_isboolean(L, idx) && !lua_toboolean(L, idx))) return 0;
    if (lua_type(L, idx) == LUA_TSTRING) {
        const char *s = lua_tostring(L, idx);
        static const int SEMI[] = {9, 11, 0, 2, 4, 5, 7}; /* A B C D E F G */
        if (s[0] < 'A' || s[0] > 'G') return luaL_error(L, "studio: \"%s\" is not a note", s);
        int n = SEMI[s[0] - 'A'], k = 1;
        if (s[k] == '#') n++, k++;
        else if (s[k] == 'b') n--, k++;
        char *end;
        long oct = strtol(s + k, &end, 10);
        if (end == s + k || *end || oct < -1 || oct > 9) return luaL_error(L, "studio: \"%s\" is not a note", s);
        n += 12 * ((int)oct + 1);
        return n >= 0 && n < 128 ? n : luaL_error(L, "studio: \"%s\" is out of range", s);
    }
    lua_Integer n = luaL_checkinteger(L, idx);
    if (n < 0 || n > 127) return luaL_error(L, "studio: note %d (0, a rest, to 127)", (int)n);
    return (int)n;
}

/* studio.notes(i, {...}): each step a note, or {note, accent = true, slide = true}, or 0 / false for a rest */
static int l_notes(lua_State *L) {
    int i = track_arg(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    int n = (int)luaL_len(L, 2);
    if (n > STUDIO_STEPS) return luaL_error(L, "studio.notes: %d steps (%d at most)", n, STUDIO_STEPS);
    uint8_t notes[STUDIO_STEPS], flags[STUDIO_STEPS];
    for (int s = 0; s < n; s++) {
        lua_rawgeti(L, 2, s + 1);
        flags[s] = 0;
        if (lua_istable(L, -1)) {
            lua_rawgeti(L, -1, 1);
            notes[s] = (uint8_t)midi_of(L, -1);
            lua_pop(L, 1);
            flags[s] = (uint8_t)((opt_bool(L, lua_gettop(L), "accent", false) ? STUDIO_ACCENT : 0) |
                                 (opt_bool(L, lua_gettop(L), "slide", false) ? STUDIO_SLIDE : 0));
        } else {
            notes[s] = (uint8_t)midi_of(L, -1);
        }
        lua_pop(L, 1);
    }
    studio_notes(i, notes, flags, n);
    return 0;
}

static const char *const REVERBS[] = {"plate", "gba", NULL};

/* studio.fx({delay, feedback, tone, reverb, size, damp, lofi}): what is left out stays as it was */
static int l_fx(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    studio_fx_params f;
    studio_fx_get(&f);
    f.delay = opt_float(L, 1, "delay", f.delay, 0.25f, 16);
    f.feedback = opt_float(L, 1, "feedback", f.feedback, 0, 0.95f);
    f.tone = opt_float(L, 1, "tone", f.tone, 0, 1);
    lua_getfield(L, 1, "reverb");
    if (!lua_isnil(L, -1)) f.reverb = luaL_checkoption(L, -1, NULL, REVERBS) == 1 ? STUDIO_GBA : STUDIO_PLATE;
    lua_pop(L, 1);
    f.size = opt_float(L, 1, "size", f.size, 0, 1);
    f.damp = opt_float(L, 1, "damp", f.damp, 0, 1);
    f.lofi = opt_bool(L, 1, "lofi", f.lofi);
    studio_fx_set(&f);
    return 0;
}

static int l_note(lua_State *L) { /* studio.note(i [, note [, accent]]): played by hand; no note lets it go */
    int i = track_arg(L, 1);
    studio_note(i, midi_of(L, 2), lua_toboolean(L, 3));
    return 0;
}

void studio_register(lua_State *L) {
    static const luaL_Reg F[] = {{"tempo", l_tempo}, {"length", l_length}, {"track", l_track}, {"steps", l_steps},
                                 {"play", l_play}, {"stop", l_stop}, {"playing", l_playing}, {"pos", l_pos},
                                 {"hit", l_hit}, {"synth", l_synth}, {"notes", l_notes}, {"note", l_note},
                                 {"fx", l_fx},
                                 {NULL, NULL}};
    luaL_newlib(L, F);
    lua_setglobal(L, "studio");
}
