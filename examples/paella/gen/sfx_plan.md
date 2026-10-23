# Paella de Combate: sound effects plan

Every effect is made in `_init` with the engine's `sound(id, {numbers})` (docs/lua.md, "Sounds made from numbers") and played
with `sfx(id, gain, {...})`. The Lua block at the end is valid as it stands: every recipe was made and played through `build/pinyol_headless --audio`
(none silent, none clipping: peaks from about -14 dBFS, the thin noisy ones, to -2, the explosions, at gain 1; the tractor's engine
loop sits low under the music).
Rules of thumb: weapons that fire fast get `pitch_var = 1` and `max = 3` (never a wall of the same sound); a cue the player
must learn (a pickup, the coin) stays exact; big events `duck()` the music; hits get `cooldown = 0.04`.

| id | what | play with |
|---|---|---|
| `KNIFE` | Chef Estrella's throwing knife: a thin swish | `pitch_var = 1, max = 3` |
| `KNIFE_TING` | the knife striking metal: a bright FM ting | with `HIT_METAL` when a knife hits |
| `FOAM` | Chef Espuma's siphon: a short wide hiss closing down | `pitch_var = 1, max = 2` |
| `CROQUETA` | Don Pinche's pan firing a croquette: a fat square *bonk* falling | `pitch_var = 2` |
| `ARROZ` | the Maestro's ladle flinging rice and hot oil: a fizzing scatter | `pitch_var = 1, max = 2` |
| `NATA` | Doña Brioche's whipped cream, a steady stream: loops while fire is held | `loop = true`, `sfx_stop` on release |
| `CORCHO` | Don Crianza's cava cork: a punchy *pop* | then `FIZZ` at gain 0.6 |
| `FIZZ` | the cava's fizz after the pop | |
| `GRENADE` | a grenade (a garlic bulb) thrown: a rising whoosh | |
| `EXPLOSION` | a big explosion (grenade, crab tank, a barrel) | `duck({to = 0.5, hold = 0.3})` |
| `EXPLO_S` | a small one (a fish-bomb, a drone) | `pitch_var = 2` |
| `HIT_METAL` | a shot on a mechanical gull: a clank | `pitch_var = 2, cooldown = 0.04` |
| `GULL_CAW` | a gull's mechanical squawk (alert, attack) | `pitch_var = 3, max = 2` |
| `GULL_DIE` | a gull flying apart in feathers and screws: a sproing sliding down | `pitch_var = 2` |
| `PLAYER_HIT` | a cook hit (before `muerte`, the jingle) | `duck()` |
| `PICKUP` | food or points: a two-note coin | exact |
| `CRATE` | a weapon crate opened (then the `arma` jingle) | |
| `AMMO` | ammunition picked up: a quick octave blip | exact |
| `JUMP`, `LAND` | jump and landing | `LAND` with `gain_var = 0.2` |
| `TRACTOR` | the Tractor-Cañón's engine: loops; follow the speed with `sfx_set(h, {pitch = 0.8 + speed / 6})` | `loop = true` |
| `SARDINE` | the tractor's sardine cannon: a deep thump | |
| `CHARGE` | El Gran Gaviotrón charging its beak cannon (0.7 s, rising) | |
| `BOSS_SHOT` | the beak cannon firing | `duck({to = 0.4})` |
| `SNIP` | a rope cut: an abuela or the fisherman freed (then `rescate`) | |
| `MENU_MOVE`, `MENU_OK` | the cursor, a choice confirmed | exact |
| `COIN` | coin in | exact |
| `TICK` | the continue countdown's digit (over the `continue` cue) | exact |

```lua
SFX = {
  KNIFE      = {wave = "noise", freq = 2400, slide = -3000, sustain = 0.02, decay = 0.08, highpass = 0.35, lowpass = 0.8, volume = 0.7},
  KNIFE_TING = {wave = "fm", freq = 2600, fm_ratio = 3.5, fm_index = 1.2, sustain = 0, decay = 0.12, volume = 0.35},
  FOAM       = {wave = "noise", freq = 900, slide = -400, attack = 0.01, sustain = 0.08, decay = 0.15, lowpass = 0.45, lowpass_sweep = -1.2, highpass = 0.1, volume = 0.6},
  CROQUETA   = {wave = "square", freq = 180, slide = -260, duty = 0.35, sustain = 0.03, decay = 0.14, punch = 0.6, lowpass = 0.5, volume = 0.4},
  ARROZ      = {wave = "noise", freq = 3000, sustain = 0.05, decay = 0.22, highpass = 0.4, lowpass = 0.9, vibrato = 0.4, vibrato_speed = 30, volume = 0.6},
  NATA       = {wave = "noise", freq = 600, sustain = 1, decay = 0, lowpass = 0.3, resonance = 0.4, volume = 0.25},
  CORCHO     = {wave = "square", freq = 700, slide = -2500, sustain = 0.01, decay = 0.06, punch = 0.9, volume = 0.5},
  FIZZ       = {wave = "noise", freq = 5000, attack = 0.02, sustain = 0.1, decay = 0.3, highpass = 0.6, volume = 0.15},
  GRENADE    = {wave = "noise", freq = 800, slide = 600, sustain = 0.05, decay = 0.12, lowpass = 0.35, lowpass_sweep = 1.5, volume = 0.5},
  EXPLOSION  = {wave = "noise", freq = 120, slide = -60, sustain = 0.15, decay = 0.9, punch = 0.8, lowpass = 0.6, lowpass_sweep = -0.5, volume = 0.6},
  EXPLO_S    = {wave = "noise", freq = 300, slide = -150, sustain = 0.05, decay = 0.35, punch = 0.6, lowpass = 0.7, lowpass_sweep = -0.8, volume = 0.5},
  HIT_METAL  = {wave = "fm", freq = 1500, fm_ratio = 2.76, fm_index = 3, sustain = 0, decay = 0.09, volume = 0.45},
  GULL_CAW   = {wave = "saw", freq = 1300, slide = -900, vibrato = 0.5, vibrato_speed = 24, sustain = 0.08, decay = 0.12, lowpass = 0.7, resonance = 0.6, volume = 0.25},
  GULL_DIE   = {wave = "square", freq = 900, slide = -1800, duty = 0.25, vibrato = 0.6, vibrato_speed = 18, sustain = 0.05, decay = 0.3, volume = 0.35},
  PLAYER_HIT = {wave = "saw", freq = 330, slide = -500, sustain = 0.03, decay = 0.18, punch = 0.5, lowpass = 0.55, volume = 0.45},
  PICKUP     = {wave = "square", freq = 988, arp = 1.5, arp_time = 0.06, duty = 0.25, sustain = 0.05, decay = 0.15, volume = 0.3},
  CRATE      = {wave = "noise", freq = 400, sustain = 0.03, decay = 0.12, lowpass = 0.4, volume = 0.5},
  AMMO       = {wave = "square", freq = 660, arp = 2, arp_time = 0.04, sustain = 0.02, decay = 0.08, volume = 0.25},
  JUMP       = {wave = "square", freq = 300, slide = 900, sustain = 0.03, decay = 0.08, volume = 0.2},
  LAND       = {wave = "noise", freq = 200, sustain = 0.01, decay = 0.06, lowpass = 0.25, volume = 0.4},
  TRACTOR    = {wave = "square", freq = 55, duty = 0.3, sustain = 1, decay = 0, vibrato = 0.15, vibrato_speed = 11, lowpass = 0.25, volume = 0.15},
  SARDINE    = {wave = "noise", freq = 150, slide = -80, sustain = 0.05, decay = 0.35, punch = 1, lowpass = 0.5, volume = 0.6},
  CHARGE     = {wave = "saw", freq = 200, slide = 900, slide_accel = 600, vibrato = 0.3, vibrato_speed = 14, attack = 0.6, sustain = 0.1, decay = 0.05, lowpass = 0.6, volume = 0.35},
  BOSS_SHOT  = {wave = "saw", freq = 1400, slide = -2600, sustain = 0.08, decay = 0.4, punch = 0.7, lowpass = 0.7, lowpass_sweep = -0.6, volume = 0.5},
  SNIP       = {wave = "noise", freq = 4000, sustain = 0.005, decay = 0.04, highpass = 0.6, volume = 0.5},
  MENU_MOVE  = {wave = "square", freq = 1320, duty = 0.125, sustain = 0.01, decay = 0.04, volume = 0.3},
  MENU_OK    = {wave = "square", freq = 880, arp = 1.5, arp_time = 0.05, duty = 0.25, sustain = 0.04, decay = 0.12, volume = 0.25},
  COIN       = {wave = "square", freq = 1046, arp = 1.335, arp_time = 0.07, duty = 0.5, sustain = 0.06, decay = 0.25, volume = 0.3},
  TICK       = {wave = "fm", freq = 1760, fm_ratio = 3.5, fm_index = 1, sustain = 0, decay = 0.15, volume = 0.4},
}
for id, numbers in pairs(SFX) do sound(id, numbers) end   -- in _init
```

Music cues the game calls (all with `{bank = "BANK"}`): `titulo`, `seleccion`, `puerto`, `calle`, `tractor` (cross-fade to it,
e.g. `music("tractor", 800, {bank = "BANK"})`), `playa`, `jefe`, `fin`, `continue` loop; `victoria`, `rescate`, `arma`,
`muerte`, `game_over` are jingles (`loop = false`; they end in silence either way). Resume a zone's song after a jingle with a
short fade (300 ms).
