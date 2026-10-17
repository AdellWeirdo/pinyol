/* What a game hears: recordings (sfx, music), sounds it makes from numbers (sound), notes on the synthesised voices
 * (tone, note), and music that changes with the game (music_layer).
 *
 *   sound(id, {wave, freq, slide, ...} | kind [, seed]) -> its numbers: a sound made into id, played by sfx(id)
 *   sfx(id [, gain [, {pitch, loop}]]) -> handle;  sfx_set(handle, {gain, pitch});  sfx_stop(handle)
 *   music(id [, fade_ms]);  music_layer(stem, gain [, fade_ms]);  tone(voice, note [, {...}]);  note(name)
 *   mic() -> level, pitch, hit, recording (nil: no microphone);  mic(false);  mic_record(id, seconds);  mic_record() */
#include <stdlib.h>

#include "lua_api.h"

#define MADE_BYTES (1024 * 1024) /* all of a game's made sounds: a minute of them */

static const char *const WAVES[] = {"square", "triangle", "saw", "sine", "noise", NULL};

/* the made sounds' numbers, as a table and back: names as in docs/lua.md */
#define FIELDS(X)                                                                                                     \
    X(freq) X(freq_min) X(slide) X(slide_accel) X(vibrato) X(vibrato_speed) X(arp) X(arp_time) X(duty) X(duty_sweep) \
    X(attack) X(sustain) X(punch) X(decay) X(lowpass) X(lowpass_sweep) X(resonance) X(highpass) X(highpass_sweep)    \
    X(volume)

static void params_from(lua_State *L, int t, synth_params *p) {
    lua_getfield(L, t, "wave");
    if (!lua_isnil(L, -1)) p->wave = luaL_checkoption(L, -1, NULL, WAVES);
    lua_pop(L, 1);
#define READ(f) p->f = opt_float(L, t, #f, p->f, -1e6f, 1e6f);
    FIELDS(READ)
#undef READ
    p->repeat = opt_float(L, t, "again", p->repeat, 0, 1e6f); /* "repeat" is a Lua keyword */
    p->seed = (uint32_t)opt_float(L, t, "seed", (float)p->seed, 0, 16777216);
    synth_clamp(p);
}

static void params_to(lua_State *L, const synth_params *p) {
    lua_createtable(L, 0, 24);
    lua_pushstring(L, WAVES[p->wave]), lua_setfield(L, -2, "wave");
#define WRITE(f) lua_pushnumber(L, p->f), lua_setfield(L, -2, #f);
    FIELDS(WRITE)
#undef WRITE
    lua_pushnumber(L, p->repeat), lua_setfield(L, -2, "again");
    lua_pushinteger(L, (lua_Integer)p->seed), lua_setfield(L, -2, "seed");
}

static int l_sound(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    if (!safe_name(id) || strchr(id, '/') || strlen(id) >= 32) return luaL_error(L, "sound \"%s\": not a sound name", id);
    synth_params p;
    synth_defaults(&p);
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *kind = lua_tostring(L, 2);
        if (!synth_recipe(kind, (uint32_t)luaL_optinteger(L, 3, 1), &p))
            return luaL_error(L, "sound \"%s\": no recipe \"%s\" (coin, laser, explosion, powerup, hit, jump, blip, "
                                 "random)", id, kind);
    } else {
        luaL_checktype(L, 2, LUA_TTABLE);
        params_from(L, 2, &p);
    }
    int max = (int)(SYNTH_MAX_S * AUDIO_HZ) + 1;
    int16_t *pcm = hal_realloc_slow(NULL, sizeof(int16_t) * (size_t)max);
    if (!pcm) return luaL_error(L, "sound \"%s\": out of memory", id);
    int n = synth_render(&p, pcm, max);
    if (n < 1) pcm[0] = 0, n = 1; /* silence, but a sound: sfx(id) plays it */
    if (audio_made_bytes() + (long)n * 2 > MADE_BYTES) {
        free(pcm);
        return luaL_error(L, "sound \"%s\": no room for it, a game makes %d KB of sounds at most", id, MADE_BYTES / 1024);
    }
    int16_t *fit = hal_realloc_slow(pcm, sizeof(int16_t) * (size_t)n);
    if (!audio_sfx_set(id, fit ? fit : pcm, n)) return luaL_error(L, "sound \"%s\": too many sounds", id);
    params_to(L, &p);
    return 1;
}

/* sfx(id [, gain [, {pitch, loop, pan, attack, decay, sustain, release, loop_start, loop_end}]]) -> a handle for sfx_set and sfx_stop (0 if it could not play) */
static int l_sfx(lua_State *L) {
    const char *id = luaL_checkstring(L, 1);
    sfx_opts o = {.gain = fin(luaL_optnumber(L, 2, 1)), .pitch = 1};
    if (!lua_isnoneornil(L, 3)) {
        luaL_checktype(L, 3, LUA_TTABLE);
        o.pitch = opt_float(L, 3, "pitch", 1, 0.0625f, 16), o.loop = opt_bool(L, 3, "loop", false);
        o.pan = opt_float(L, 3, "pan", 0, -1, 1), o.reverb = opt_float(L, 3, "reverb", 0, 0, 1);
        /* the envelope: any of its four asked for makes one (the rest: no attack, no decay, full sustain, no release) */
        const float a = opt_float(L, 3, "attack", -1, -1, 30), d = opt_float(L, 3, "decay", -1, -1, 30);
        const float su = opt_float(L, 3, "sustain", -1, -1, 1), r = opt_float(L, 3, "release", -1, -1, 30);
        o.env = a >= 0 || d >= 0 || su >= 0 || r >= 0;
        o.attack = a < 0 ? 0 : a, o.decay = d < 0 ? 0 : d, o.sustain = su < 0 ? 1 : su, o.release = r < 0 ? 0 : r;
        /* a loop's two points, in seconds into the clip */
        const float ls = opt_float(L, 3, "loop_start", -1, -1, 1e4f), le = opt_float(L, 3, "loop_end", -1, -1, 1e4f);
        if (ls >= 0 && le > ls) o.loop_start = (int)(ls * AUDIO_HZ), o.loop_end = (int)(le * AUDIO_HZ);
    }
    lua_pushinteger(L, safe_name(id) ? audio_sfx_play_opts(id, &o) : 0); /* it keeps gain in 0..1 */
    return 1;
}

static int l_sfx_set(lua_State *L) { /* sfx_set(handle, {gain, pitch, pan}): a sound that is playing, changed */
    int h = (int)luaL_checkinteger(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    audio_sfx_adjust(h, opt_float(L, 2, "gain", -1, -1, 1), opt_float(L, 2, "pitch", -1, -1, 16));
    lua_getfield(L, 2, "pan");
    if (!lua_isnil(L, -1)) audio_sfx_pan(h, opt_float(L, 2, "pan", 0, -1, 1));
    lua_pop(L, 1);
    return 0;
}

static int l_sfx_stop(lua_State *L) {
    if (lua_isnoneornil(L, 1)) return 0;
    audio_sfx_stop((int)luaL_checkinteger(L, 1));
    return 0;
}

/* reverb(room [, wet [, {music, ambient}]]): a room of the PlayStation's for the game's sounds: "room", "studio_small",
 * "studio_medium", "studio_large", "hall", "half_echo", "space_echo" or "delay"; wet (default 0.5) how much of it
 * comes back; music and ambient (default 0) how much of those go into it (sfx sends with its reverb). reverb() or
 * reverb(false) lets it fade out. */
static int l_reverb(lua_State *L) {
    if (lua_isnoneornil(L, 1) || lua_isboolean(L, 1)) {
        audio_reverb(-1, 0, 0, 0);
        return 0;
    }
    const char *name = luaL_checkstring(L, 1);
    int room = reverb_find(name);
    if (room < 0) return luaL_error(L, "reverb: no room \"%s\" (room, studio_small, studio_medium, studio_large, hall, half_echo, space_echo, delay)", name);
    float wet = fin(luaL_optnumber(L, 2, 0.5)), music = 0, amb = 0;
    if (!lua_isnoneornil(L, 3)) {
        luaL_checktype(L, 3, LUA_TTABLE);
        music = opt_float(L, 3, "music", 0, 0, 1), amb = opt_float(L, 3, "ambient", 0, 0, 1);
    }
    audio_reverb(room, wet < 0 ? 0 : wet > 1 ? 1 : wet, music, amb);
    return 0;
}

static int l_volume(lua_State *L) { /* volume(v): everything the game sounds, 0 (silent) to 1; each game starts at 1 */
    float v = fin(luaL_checknumber(L, 1));
    audio_master(v < 0 ? 0 : v > 1 ? 1 : v, 60);
    return 0;
}

static int l_sfx_on(lua_State *L) { /* sfx_on(handle) -> is that sound still playing? */
    lua_pushboolean(L, audio_sfx_playing((int)luaL_checkinteger(L, 1)));
    return 1;
}

/* music_layer(stem, gain [, fade_ms]): a WAV played by music() has one stem per channel (drums, bass, melody...);
 * each comes in or out, so the music follows the game (a calm part, then the drums when the boss comes) */
/* music_pan(pan [, fade_ms]): the song placed between the ears, -1 (left) to 1 (right), moving there over the fade */
static int l_music_pan(lua_State *L) {
    float p = fin(luaL_checknumber(L, 1));
    audio_music_pan(p < -1 ? -1 : p > 1 ? 1 : p, (int)luaL_optinteger(L, 2, 300));
    midi_pan(p);
    return 0;
}

/* ambient(id [, fade_ms [, {pan}]]): a bed of sound under the game (a room's murmur, rain), looping, crossfaded with the one
 * before it; audio/<id>.wav or .spum; ambient() fades it out. Up to three at once while they cross. */
static int l_ambient(lua_State *L) {
    const int fade = (int)luaL_optinteger(L, 2, 1000);
    if (lua_isnoneornil(L, 1)) {
        audio_ambient(NULL, fade);
        return 0;
    }
    const char *id = luaL_checkstring(L, 1);
    float pan = 0;
    if (lua_istable(L, 3)) pan = opt_float(L, 3, "pan", 0, -1, 1);
    if (safe_name(id)) audio_ambient_pan(id, fade, pan);
    return 0;
}

static int l_music_layer(lua_State *L) {
    int stem = (int)luaL_checkinteger(L, 1);
    if (stem < 0 || stem >= MAX_STEMS) return luaL_error(L, "music_layer: stem %d does not exist (0 to %d)", stem, MAX_STEMS - 1);
    float g = fin(luaL_checknumber(L, 2));
    audio_music_layer(stem, g < 0 ? 0 : g > 1 ? 1 : g, (int)luaL_optinteger(L, 3, 500));
    return 0;
}

/* music(id [, fade_ms]) loops audio/<id>.mod (a tracker module) or audio/<id>.wav; music() stops it */
static int l_music(lua_State *L) {
    int fade = (int)luaL_optinteger(L, 2, lua_isnoneornil(L, 1) ? 500 : 300);
    if (lua_isnoneornil(L, 1)) {
        audio_music_stop(fade);
        mod_stop(fade);
        midi_stop(fade);
        audio_music_clock(0);
        return 0;
    }
    const char *id = luaL_checkstring(L, 1);
    char path[384];
    snprintf(path, sizeof path, "%s/audio/%s.mod", G.game_dir, id);
    FILE *f = safe_name(id) ? fopen(path, "rb") : NULL;
    if (f) { /* a module: it replaces any music */
        fclose(f);
        audio_music_stop(fade);
        midi_stop(fade);
        if (!mod_play(path, 1)) audio_music_clock(0);
        return 0;
    }
    snprintf(path, sizeof path, "%s/audio/%s.mid", G.game_dir, id);
    f = safe_name(id) ? fopen(path, "rb") : NULL;
    if (f) { /* a MIDI file, played by a bank of samples: music("SONG", 300, {bank = "KIT", loop = true, volume = 1}) */
        fclose(f);
        audio_music_stop(fade);
        mod_stop(fade);
        char bank[48] = "BANK";
        bool loop = true;
        float volume = 1;
        if (lua_istable(L, 3)) {
            lua_getfield(L, 3, "bank");
            if (lua_isstring(L, -1) && safe_name(lua_tostring(L, -1))) snprintf(bank, sizeof bank, "%s", lua_tostring(L, -1));
            lua_pop(L, 1);
            loop = opt_bool(L, 3, "loop", true), volume = opt_float(L, 3, "volume", 1, 0, 1);
        }
        if (!midi_play(id, bank, loop, volume, fade)) audio_music_clock(0);
        return 0;
    }
    static const float all[8] = {1, 1, 1, 1, 1, 1, 1, 1};
    midi_stop(fade);
    mod_stop(fade);
    if (safe_name(id)) audio_music_start(id, 0, 0, all, fade);
    return 0;
}


/* music_time() -> seconds into the song music() started, as the player hears it now (what is queued for the speaker
 * taken off), going on across its loops; nil when no song plays. For notes on the beat. */
static int l_music_time(lua_State *L) {
    double s;
    if (!audio_music_time(&s)) return lua_pushnil(L), 1;
    lua_pushnumber(L, s);
    return 1;
}

/* tone(voice, freq or "C4" [, {wave, vol, duty, attack, decay, sustain, len, release, slide}]); tone(voice) lets go */
static int l_tone(lua_State *L) {
    int ch = (int)luaL_checkinteger(L, 1);
    if (ch < 0 || ch >= PSG_VOICES) return luaL_error(L, "tone: voice %d does not exist (0 to %d)", ch, PSG_VOICES - 1);
    if (lua_isnoneornil(L, 2)) {
        psg_release(ch);
        return 0;
    }
    float hz = lua_type(L, 2) == LUA_TSTRING ? psg_note_hz(lua_tostring(L, 2)) : (float)luaL_checknumber(L, 2);
    if (!(hz > 0 && hz < AUDIO_HZ / 2)) return luaL_error(L, "tone: '%s' is not a note or a frequency", luaL_tolstring(L, 2, NULL));
    psg_note n = {.wave = PSG_SQUARE, .freq = hz, .vol = 0.5f, .duty = 0.5f, .attack = 0.005f, .decay = 0.25f,
                  .release = 0.03f};
    if (!lua_isnoneornil(L, 3)) {
        luaL_checktype(L, 3, LUA_TTABLE);
        lua_getfield(L, 3, "wave");
        if (!lua_isnil(L, -1)) n.wave = (uint8_t)luaL_checkoption(L, -1, NULL, WAVES);
        lua_pop(L, 1);
        n.vol = opt_float(L, 3, "vol", n.vol, 0, 1), n.duty = opt_float(L, 3, "duty", n.duty, 0.01f, 0.99f);
        n.attack = opt_float(L, 3, "attack", n.attack, 0, 60), n.decay = opt_float(L, 3, "decay", n.decay, 0, 60);
        n.sustain = opt_float(L, 3, "sustain", 0, 0, 1), n.len = opt_float(L, 3, "len", 0, 0, 600);
        n.release = opt_float(L, 3, "release", n.release, 0, 60), n.slide = opt_float(L, 3, "slide", 0, -1e5f, 1e5f);
    }
    psg_play(ch, &n);
    return 0;
}

static int l_note(lua_State *L) { /* note("C4") -> 261.63 Hz */
    lua_pushnumber(L, psg_note_hz(luaL_checkstring(L, 1)));
    return 1;
}


/* mic() -> level 0..1, pitch in Hz (0: no clear note), hit (a sudden sound this tick), recording; nil when there is
 * no microphone. The first call starts listening; mic(false) stops. */
static int l_mic(lua_State *L) {
    if (lua_isboolean(L, 1) && !lua_toboolean(L, 1)) {
        mic_close();
        return 0;
    }
    float level, pitch;
    bool hit, rec;
    const char *kind;
    if (!mic_open() || !mic_read(&level, &pitch, &hit, &rec, &kind)) return lua_pushnil(L), 1;
    lua_pushnumber(L, level), lua_pushnumber(L, pitch), lua_pushboolean(L, hit), lua_pushboolean(L, rec);
    if (kind) lua_pushstring(L, kind);
    else lua_pushnil(L);
    return 5;
}

/* mic_record(id, seconds): what the microphone hears becomes the sound id (sfx(id)) when the time is up (10 s at
 * most); mic_record() ends it sooner. True if it started. */
static int l_mic_record(lua_State *L) {
    if (lua_isnoneornil(L, 1)) {
        mic_record_stop();
        return 0;
    }
    const char *id = luaL_checkstring(L, 1);
    if (!safe_name(id) || strchr(id, '/') || strlen(id) >= 32) return luaL_error(L, "mic_record \"%s\": not a sound name", id);
    float s = fin(luaL_checknumber(L, 2));
    if (audio_made_bytes() + (long)((s > 10 ? 10 : s) * AUDIO_HZ) * 2 > MADE_BYTES)
        return luaL_error(L, "mic_record \"%s\": no room for it, a game makes %d KB of sounds at most", id, MADE_BYTES / 1024);
    lua_pushboolean(L, mic_open() && mic_record(id, s));
    return 1;
}

void sound_register(lua_State *L) {
    static const luaL_Reg F[] = {{"sound", l_sound}, {"sfx", l_sfx}, {"sfx_set", l_sfx_set}, {"sfx_stop", l_sfx_stop},
                                 {"sfx_on", l_sfx_on}, {"music", l_music}, {"music_layer", l_music_layer},
                                 {"music_time", l_music_time},
                                 {"tone", l_tone}, {"note", l_note}, {"mic", l_mic},
                                 {"mic_record", l_mic_record}, {"volume", l_volume}, {"reverb", l_reverb}, {"music_pan", l_music_pan}, {"ambient", l_ambient}, {NULL, NULL}};
    lua_pushglobaltable(L);
    luaL_setfuncs(L, F, 0);
    lua_pop(L, 1);
}
