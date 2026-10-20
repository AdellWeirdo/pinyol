# pinyol game format

Reference for the data a game needs to run on the pinyol engine. A game is a folder of JSON, runtime
assets, WAV files and fonts; no C is involved. Everything below was read from the engine source (`src/`).
The validator (`content_validate()` in `src/content.c`) is the final word on what is required and allowed.
Where this document says "validator", it means a check that `pinyol_headless --validate` makes.

Units used throughout: **px** = logical world pixel (the world is 240×160 and drawn 2× to the 480×320
screen); **native px** = screen pixel; **tile** = 16×16 px; **tick** = 1/60 s; **ms** = milliseconds.

## Minimal game

```
games/mygame/
  game.json        title, start zone, zone and dialogue lists, speakers, flags
  tiles.json       tile legend ({"families": {}, "legend": {...}} is enough with painted backgrounds)
  items.json  events.json  notebook.json  sequences.json  listen.json  puzzles.json   ({} each is fine)
  music.json       must define a "title" cue and an "end" cue (validator)
  zones/Z01.json   one room: size, floor grid, a "safe" spawn
  dialogues/       one JSON file per dialogue
  assets/          <ID>.rgb565 + <ID>.meta.json (+ <ID>.mask); missing art draws a checkerboard
  audio/           <ID>.wav, PCM 16-bit at 22050 Hz
  fonts/           FONT_MAIN.fnt  FONT_MAIN_L.fnt  FONT_BOLD.fnt  FONT_BOLD_L.fnt
```

`uv run tools/new_game.py games/mygame` writes such a game, with placeholder art, a dialogue, an item and an end.
Check it with `pinyol_headless --game games/mygame --validate --strict-assets`. This checks content and art used in
the first frame. Play each route with a test script to check art loaded later.

## Contents

1. [Folder layout](#1-folder-layout)
2. [Units, coordinates and controls](#2-units-coordinates-and-controls)
3. [game.json](#3-gamejson)
4. [Flags, conditions, effects and events](#4-flags-conditions-effects-and-events)
5. [Zones and tiles](#5-zones-and-tiles)
6. [Dialogues](#6-dialogues)
7. [Sequences](#7-sequences)
8. [Items](#8-items)
9. [Notebook](#9-notebook)
10. [Listening points](#10-listening-points)
11. [Puzzles](#11-puzzles)
12. [Arena (side-view fights)](#12-arena-side-view-fights)
13. [Music and sound](#13-music-and-sound)
14. [Assets (runtime image format)](#14-assets-runtime-image-format)
15. [Fonts (FNT1)](#15-fonts-fnt1)
16. [Text rules](#16-text-rules)
17. [Validation and test scripts](#17-validation-and-test-scripts)
18. [Engine limits](#18-engine-limits)
19. [Known quirks and current limitations](#19-known-quirks-and-current-limitations)

---

## 1. Folder layout

| Path | Required | Notes |
|---|---|---|
| `game.json`, `tiles.json`, `items.json`, `events.json`, `notebook.json`, `sequences.json`, `listen.json`, `puzzles.json`, `music.json` | yes, all 9 | Each must parse as JSON. If one is missing or invalid the engine logs `required content missing or invalid: <file>` and the game does not start ("game folder incomplete"). Use `{}` for the ones you don't need. |
| `arena.json` | no | Only for games that use the `["arena", ID]` effect. |
| `zones/<ZONE>.json` | one per zone | Loaded the first time the zone is entered. |
| `dialogues/<D_ID>.json` | one per dialogue | Loaded the first time it is used. |
| `assets/` | in practice | `<ID>.rgb565`, `<ID>.meta.json`, optional `<ID>.mask` (section 14). A missing picture draws a magenta/ink checkerboard; `--strict-assets` treats any requested missing or invalid picture as an error. Only pictures used during the checked run are examined. |
| `audio/` | the music.json title and end cues, at least | `<ID>.wav` (section 13). The validator checks almost every sound referenced from data (not conduit `sfx`/`sfx_turn` or the music.json `title`/`end` `ambient`); at runtime a missing sound is silent. |
| `fonts/` | yes | `FONT_MAIN.fnt`, `FONT_MAIN_L.fnt`, `FONT_BOLD.fnt`, `FONT_BOLD_L.fnt` (section 15). The game does not start without all four. |
| `saves/` | created by the engine | Save slots and `settings.txt`. Desktop tools can redirect it with `--saves DIR`. |
| `cover.rgb565` | no | The game's cover in the console's menu: 240×160 RGB565, little endian (`tools/cover.py` makes it from the game's title screen or any picture). Without one, an adventure's `assets/BG_TITLE.rgb565` of that size is used, or the menu draws a card with the title. |

On the console the microSD holds `games/<id>/`. The console's menu (`firmware/cirera`, a pinyol game itself) shows
every folder that contains a parseable `game.json`, with its `title` (folder name if missing), its `subtitle` and its
cover. If that menu cannot run, the firmware's own list (`firmware/main/launcher.c`) shows them instead, borrowing
`FONT_BOLD_L` and `FONT_MAIN` from the first game.

### Saves

| Slot | Written by |
|---|---|
| `auto` | entering a zone through an exit or a `zone` effect (not during a sequence), events with `"save": true`, the `save` effect or sequence step, a chapter start, a drill step completed with `step_flag` |
| `manual` | pause menu "Guardar partida" |
| `prefinal` | the `checkpoint` effect or sequence step |

Each slot is two files, `<slot>_a.sav` and `<slot>_b.sav`; the older one is overwritten so a cut write never
loses the last good save. "Continuar" on the title screen loads the newest valid file of the three slots.
File format: a 16-byte little-endian header (`"BPSV"`, u16 schema = 1, u16 `content_version`, u32 payload
length, u32 CRC-32 of the payload) followed by text lines: `seq=`, `zone=`, `pos=x,y`, `facing=`, `p01=x,y,rot`
and one `f <flag>=<value>` line per non-zero flag. Flags are stored by name, so adding new flags to a game keeps
old saves valid. `settings.txt` holds the options (`large`, `portraits`, `bag`, `vol`, `tones`).

### A complete minimal game

This is the smallest folder that validates and runs (fonts copied from any game; the WAV is one second of
mono silence at 22050 Hz).

`game.json`
```json
{
  "title": "My Game",
  "player": {"speaker": "HERO", "sprite": "HE"},
  "start": {"zone": "Z01", "spawn": "safe"},
  "zones": ["Z01"],
  "dialogues": ["D_SIGN"],
  "speakers": {"HERO": {"name": "Hero", "color": "#2E5C9A"}},
  "flags": ["sign_read"]
}
```

`tiles.json`
```json
{"families": {}, "legend": {"#": null, ".": null}}
```

`items.json`, `events.json`, `notebook.json`, `sequences.json`, `listen.json`, `puzzles.json`: `{}`

`music.json`
```json
{"title": {"cue": "MUS_MAIN"}, "end": {"cue": "MUS_MAIN"},
 "cues": {"MUS_MAIN": {"layers": [[1], [1], [1], [1]]}}}
```

`zones/Z01.json`
```json
{
  "name": "Room",
  "size": [15, 10],
  "floor": [
    "###############",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "###############"
  ],
  "spawns": {"safe": [7, 6, "N"]},
  "hotspots": [{"id": "sign", "name": "Sign", "at": [7, 3], "dlg": "D_SIGN"}]
}
```

`dialogues/D_SIGN.json`
```json
{"entry": [{"if": "!sign_read", "node": "first"}, {"node": "again"}],
 "nodes": {
   "first": {"lines": [["HERO", "It says: welcome."]], "do": [["set", "sign_read"]]},
   "again": {"lines": [["HERO", "Still says welcome."]]}
 }}
```

`audio/MUS_MAIN.wav`, `fonts/*.fnt`. With no art at all the room draws as checkerboards, but everything works.

---

## 2. Units, coordinates and controls

- Screen: 480×320 native px. The world is rendered at 240×160 px and scaled 2×. Every zone, sprite, collision
  and arena coordinate is in world px.
- Tiles are 16×16 px. A 15×10-tile zone fills exactly one screen; larger zones scroll.
- Grid positions are `[tx, ty]` in tiles from the top-left. An object placed with `"at": [tx, ty]` has its
  anchor (the "feet" point) at **(tx·16 + 8, ty·16 + 12)** px, plus `"off": [dx, dy]` px if given. Spawns use the
  same point. Sprites are drawn with their meta.json `anchor` on that point.
- Depth: props, NPCs and the player are sorted by the y of their anchor.
- The player's collision box is 10×6 px with its top-left at (x−5, y−4) from the feet.
- Camera: centred on the player 16 px above the screen centre, clamped to the zone edges. A zone smaller than the
  screen in one axis is centred in that axis. Sequences can offset it (`camera` step).
- Native px (480×320) are used only by `title_layout`, the default puzzle's layout, touch input and the script
  commands `p01 ...`.
- Directions are `"N"`, `"E"`, `"S"`, `"W"` (`"O"` is also read as west; anything else is south). Sprite sheets
  with directions store them in the order N, E, S, W.
- Time: 60 ticks per second. Sequences, listening points and music fades use ms; ambient events use seconds;
  arena and drill parameters use ticks.

Controls (for reference when writing hints): D-pad moves; **A** interacts and advances text; **B** goes back;
**C** cycles between targets in reach, asks puzzles for help and skips skippable scenes; **MENU** opens the bag
(or pauses when the bag is empty); **START** pauses. The notebook opens from the pause menu, from the bag with C,
or with J on desktop. Touch works on every screen.

---

## 3. game.json

| Key | Type | Default | What it does |
|---|---|---|---|
| `title` | string | none | Title-screen text when there is no `LOGO` asset; console game list. Before the title screen, every game shows the engine's careta, POWERED BY PINYOL (3 s; docs/lua.md, "The careta"). |
| `subtitle` | string | `""` | Plate on the title screen; second line in the console game list. |
| `tagline` | string | none | Caption at the bottom of the title screen. |
| `end_text` | string | `"Fin"` | End-screen line when the current chapter has no `end_text`. |
| `content_version` | int | `1` | Written into saves. A save with a different value still loads, but the player is put on the zone's `safe` spawn. |
| `start` | object | see below | Where "Nueva partida" begins. |
| `zones` | [string] | `[]` | Zone IDs the validator checks; also the valid targets for exits, `zone` effects, `visited:` flags, chapter starts and music.json keys. The runtime loads `zones/<id>.json` on demand either way. |
| `dialogues` | [string] | `[]` | Dialogue IDs the validator checks node by node. Dialogues not listed are only checked where referenced. |
| `speakers` | object | `{}` | Speaker IDs used in lines (below). |
| `expressions` | [string] | `[]` | Portrait expression names (below). |
| `player` | object | absent | Player speaker and sprite prefix (below). |
| `flags` | [string] | `[]` | Declared plain flag names (section 4). No `:` allowed. |
| `enums` | object | `{}` | Named-value flags (section 4). |
| `theme` | object | defaults | UI colours (below). |
| `title_layout` | object | defaults | Title screen positions (below). |
| `chapters` | [object] | absent | Chapter structure and end screens (below). |
| `objectives` | [object] | absent | Current-objective line under the location sign (below). |
| `bag_label` | string | `"Bolsa"` | Title of the bag screen and of its button hints. |
| `assist_flag` | string | absent | Flag toggled by the pause menu's "Ayudas" option (the option only appears when this key exists). Must be a declared flag. |

The example games also carry `id`, `chapter` and `engine`; the engine does not read them.

### start

```json
"start": {"zone": "Z01", "spawn": "start", "seq": "SEQ_INTRO"}
```

| Key | Default | Notes |
|---|---|---|
| `zone` | `"Z01"` | Not checked by the validator. |
| `spawn` | `"safe"` | Unknown names fall back to `safe`. |
| `seq` | none | Sequence started on arrival. Takes precedence over `dlg`. Not checked by the validator. |
| `dlg` | none | Dialogue reference opened on arrival (validated). |

### player

```json
"player": {"speaker": "SUKY", "sprite": "SU"}
```

| Key | Default | Notes |
|---|---|---|
| `speaker` | `"KLAUS"` | Speaker ID the player talks as (`say` effects, spoken choices, item descriptions). |
| `sprite` | `"KL"` | Prefix of the player's sprites, at most 7 characters: `<sprite>_IDLE`, `_WALK`, `_INTERACT`, `_LISTEN`, `_DESCEND` (section 14). |
| `bag_option` | `true` when there is no `player` key, else `false` | Offers the "Bolso" option, which switches the player's sprites and portrait to `<ID>_B` variants when they exist. |

The player's portrait is `speakers[<speaker>].portrait`, or `"PT_KLAUS"` when that speaker has none.

### speakers and expressions

```json
"speakers": {
  "HERO": {"name": "Hero", "portrait": "PT_HERO", "color": "#2E5C9A", "blip": "SFX_VOICE_HERO"},
  "NARRATOR": {"name": "Note", "color": "#8B6548"}
},
"expressions": ["neutral", "happy", "worried"]
```

| Key | Default | Notes |
|---|---|---|
| `name` | none | Name tag over the dialogue box. |
| `color` | `#426751` | Name tag colour, `"#RRGGBB"`. |
| `portrait` | none | Asset drawn at native size next to the box; its frame is the expression index. Hidden when the player turns "Retratos" off. |
| `blip` | none | Mono SFX played every 5 characters while that speaker's text types. When any speaker has one, the pause menu offers "Tonos de voz". |

In lines, a speaker is written `"HERO"` or `"HERO:happy"`; the part after `:` picks the portrait frame by its
index in `expressions` (frame 0 when absent or unknown). `"SUB"` is reserved for sound subtitles and needs no
`speakers` entry: in a sequence `line` step it shows the "Sonido" tag and no portrait. In dialogue files use the
`{"sub": "text"}` line form instead (an array line with speaker `SUB` shows no tag at all).

### theme

```json
"theme": {"corners": "cut", "paper": "#E4E8EA", "ink": "#0D1B2A", "terra": "#C8473A"}
```

| Key | Default | Used for |
|---|---|---|
| `ink` | `#19332C` | borders, main text, screen background behind the world |
| `paper` | `#F2E9D2` | panels and plates |
| `paper_sel` | `#DFCFA8` | selected rows, inner lines |
| `terra` | `#A95743` | title plates, pointers, warnings |
| `ochre` | `#AF743A` | highlights, lit states |
| `dim` | `#8C8570` | disabled and secondary text |
| `brown` | `#5B402E` | secondary text, puzzle backgrounds |
| `corners` | `"round"` | `"cut"` chamfers panels and plates |

Colours must be exactly `#` plus 6 hex digits; anything else keeps the default.

### title_layout

Native px. `BG_TITLE` (240×160, drawn 2×; brown fill if missing) and `LOGO` (native size; when missing, the
`title` text is drawn in a panel) are the title-screen assets.

| Key | Default | Meaning |
|---|---|---|
| `logo` | `[132, 6]` | `[centre x, top y]` of `LOGO` |
| `menu` | `[246, 66]` | `[x, y]` of the menu panel (moved up if it would overflow the bottom or the tagline) |
| `sub` | `[132, 234]` | `[centre x, y]` of the subtitle plate |

### chapters

One save carries on across chapters. Index 0 is the first chapter.

```json
"chapters": [
  {"id": "C1", "title": "The Cracks", "done": "c1_done", "end_text": "End of chapter 1 · The Cracks",
   "load_slot": "prefinal", "load_label": "Load before the descent"},
  {"id": "C2", "title": "The Buried Street", "started": "c2_started", "done": "c2_done",
   "start": {"do": [["set", "c2_started"]], "zone": "Z08", "spawn": "c2_start", "seq": "SEQ_C2_START"},
   "after": {"zone": "Z01", "spawn": "safe", "label": "Keep playing"}}
]
```

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Only used in validator messages. |
| `title` | string | Meant for the previous chapter's end screen as "Continuar: <title>". In the current code that label only survives when it is too wide (it then reads "Continuar"); see section 19. |
| `started` | condition | The current chapter is the last chapter (from index 1) whose `started` holds; otherwise chapter 0. |
| `done` | condition | When it holds and the player picks "Continuar" on the title screen, the end screen appears instead of the world. Without `done` the test is the flag `first_descent_complete` (section 19). |
| `end_text` | string | End-screen line. If too wide it breaks at `" · "`. |
| `start` | object | `{do, zone, spawn, seq}`: how the end screen's "Continuar" begins this chapter: runs `do`, enters `zone`/`spawn` (spawn default `"safe"`), autosaves, starts `seq`. Validator: `zone` must be in `game.json` `zones`; `seq` must exist. |
| `load_slot` | string | Slot loaded by the end screen's third option. Default `"prefinal"`. |
| `load_label` | string | Label of that option. The option exists only when this key is present, and is enabled when the slot holds a valid save. |
| `after` | object | `{zone, spawn, label}`, used only when there is no next chapter: the first option (label default "Seguir jugando") returns to that zone (spawn default `"safe"`) with everything kept. `zone` has no default and is not checked by the validator: always set it. Without `after` the option reads "Continuará…" and is disabled. |

The end screen is reached with the `end` effect or sequence step.

### objectives

The first entry whose `if` holds is shown under the location sign. An entry with empty `text` shows nothing,
which is how to stop showing objectives.

```json
"objectives": [
  {"if": "game_done", "text": ""},
  {"if": "water_known", "text": "Shut the water and clear the drain",
   "checks": [{"icon": "IC_VALVE", "if": "valve_closed"}, {"icon": "IC_GRATE", "if": "drain_cleared"}]},
  {"if": "c2_started", "text": "Find where the stairs lead"}
]
```

`checks` are small native-size icons with a box ticked while their `if` holds. Validator: the text must fit on
one line (text width + 40 ≤ 464 native px) in the regular and the large font.

---

## 4. Flags, conditions, effects and events

### Flags

All persistent state is named integer flags (16-bit signed). An unset flag is 0.

| Name form | Meaning | Set by |
|---|---|---|
| `name` | any declared name in `game.json` `flags` | effects (`set`, `clear`), puzzle state flags, script `flag` |
| `enum_name` | a key of `game.json` `enums`; value = index of a named value | `["set", "enum_name", "value_name"]` |
| `item:IT_X` | the player carries item `IT_X` | `give`, `take` |
| `note:N01` | notebook entry `N01` was added | `note` |
| `visited:Z01` | zone `Z01` was entered at least once | engine |
| `seen:D_X.node` | dialogue node was entered | engine |
| `topic:D_X.choice` | a choice with that `id` was picked in dialogue `D_X` | engine |

```json
"flags": ["box_open", "photo_examined"],
"enums": {"bread_status": ["not_offered", "offered", "carrying", "delivered"]}
```

Validator: every plain name used anywhere must be in `flags` or be an `enums` key; names in `flags` must be
strings without `:`; prefixed names must point at something that exists (an item, a notebook entry, a zone listed
in `game.json`, a dialogue node, a choice `id`); other prefixes are errors; enum value names must exist.

The engine itself reads a few flag names; see section 19.

### Conditions

| Form | True when |
|---|---|
| absent or `null` | always |
| `"flag"` | the flag is not 0 (any prefixed form works: `"item:IT_KEY"`, `"seen:D_X.intro"`) |
| `"!flag"` | the flag is 0 |
| `["eq", flag, v]` | flag equals `v` (a number or an enum value name) |
| `["ge", flag, v]` | flag ≥ `v` |
| `["has", ITEM]` | the item is carried |
| `["seen", "D_X.node"]` | that node was entered |
| `["topic", "D_X.choice"]` | that choice was picked |
| `["visited", ZONE]` | that zone was entered |
| `["open", PUZZLE]` | that puzzle is on screen right now |
| `["using", ITEM]` | the dialogue on screen was opened by using or showing that item |
| `["not", c]` | `c` is false |
| `["and", c1, c2, ...]` | all hold |
| `["or", c1, c2, ...]` | any holds |
| `[c1, c2, ...]` | all hold (a list whose first element is not an operator is an implicit `and`) |

An enum value name that is not in the enum evaluates as -1. A number or an object is not a condition
(validator error; false at runtime).

Examples, one per form:

```json
"box_open"
"!seen:D_CASA.intro"
["eq", "bread_status", "carrying"]
["ge", "trust", 2]
["has", "IT_KEY"]
["seen", "D_BAR.thanks"]
["topic", "D_PANADERA.foto"]
["visited", "Z07"]
["open", "T02"]
["using", "IT_PHOTO"]
["not", ["has", "IT_KEY"]]
["and", "shelf_moved", ["has", "IT_KEY"], "!service_door_open"]
["or", "panel_open", "service_door_open"]
["shelf_moved", "!service_door_open"]
```

### Effects

Effects are always a list of arrays: `[[op, args...], ...]`, run in order. Effects that start something
(`seq`, `dlg`, `puzzle`...) push it on screen; the rest of the list still runs immediately. Nesting
(event → event, zone → on_enter → zone) stops at depth 16.

| Op | Arguments | Does | Example |
|---|---|---|---|
| `set` | flag [, value] | flag = 1, or `value` (number or enum value name) | `["set", "box_open"]`, `["set", "bread_status", "carrying"]` |
| `clear` | flag | flag = 0 | `["clear", "node_playing"]` |
| `give` | ITEM | sets `item:ITEM` | `["give", "IT_KEY"]` |
| `take` | ITEM | clears `item:ITEM` | `["take", "IT_PARCEL"]` |
| `note` | ENTRY | adds a notebook entry once: named sound `note`, toast "Nueva nota: <title>" | `["note", "N05"]` |
| `event` | EV | runs an event if its `if` holds | `["event", "EV_BOX_OPEN"]` |
| `seq` | SEQ | starts a sequence (ignored while another one runs) | `["seq", "SEQ_DOOR"]` |
| `listen` | L | starts a listening point | `["listen", "L01"]` |
| `puzzle` | P | opens a puzzle | `["puzzle", "P01"]` |
| `arena` | A [, `"practice"`] | starts a fight from arena.json; with `"practice"` a win runs `practice_win` | `["arena", "A01"]` |
| `dlg` | ref | opens a dialogue: `"D_X"` (its entry), `"D_X.node"`, or `"@text"` (a one-off player line) | `["dlg", "D_CASA.exit_blocked"]` |
| `say` | text | the player says a one-off line | `["say", "Locked."]` |
| `zone` | ZONE [, spawn] | goes to a zone; spawn default `"safe"`; an unknown spawn falls back to `safe` | `["zone", "M02", "from_street"]` |
| `sfx` | ID | plays a sound effect | `["sfx", "SFX_DOOR"]` |
| `voice` | ID | plays a streamed one-shot (spoken lines, long clips) | `["voice", "VO_ECHO_01"]` |
| `music` | CUE | forces a music cue until the next zone change, at tension 3 | `["music", "MUS_UNDER"]` |
| `audio_fade` | none | fades the ambience out until the next zone change | `["audio_fade"]` |
| `when` | cond, effects | runs the effects if the condition holds | `["when", "!seen:D_CASA.exit", [["dlg", "D_CASA.exit"]]]` |
| `save` | none | writes the `auto` slot | `["save"]` |
| `checkpoint` | none | writes the `prefinal` slot | `["checkpoint"]` |
| `end` | none | shows the end screen (chapter end) | `["end"]` |

Validator: every referenced item, note, event, sequence, listening point, puzzle, arena, dialogue and zone must
exist; flags must be declared; enum value names must exist; `sfx`/`voice` WAVs must be valid mono files; `music`
cues must be defined in music.json; any other op is an error. Because flags are sets, giving an item twice or
adding a note twice changes nothing.

### events.json

```json
{
  "EV_BOX_OPEN": {"if": "!box_open", "seq": "SEQ_BOX", "save": true,
                  "do": [["give", "IT_KEY"], ["set", "box_open"], ["note", "N01"]]},
  "invariants": [["or", "!door_open", "key_found"]]
}
```

| Key | Meaning |
|---|---|
| `if` | condition; when false the event does nothing |
| `do` | effects |
| `save` | `true`: autosave after the effects |
| `seq` | sequence started after the effects |

Order when an event runs: `if` → `do` → invariant check → autosave → `seq`. Guard events with their own flag
(`"if": "!box_open"`) so they run once.

`"invariants"` is a reserved key: a list of conditions that must always hold. They are checked after every event
(a broken one is logged as `INVARIANT BROKEN`) and on every tick by the script runner while the game is being
played (a broken one fails the script).

---

## 5. Zones and tiles

### tiles.json

```json
{
  "families": {"TS_STONE": [0, 20], "TS_WOOD": [20, 16], "TS_WALL": [36, 24]},
  "legend": {" ": null, ":": "TS_STONE_00", ".": "TS_WOOD_00", "#": "TS_WALL_00"}
}
```

- `families`: `{FAMILY: [first_index, count]}`. A tile name is `<FAMILY>_<N>`: the family is everything before
  the last underscore, `N` must be below `count`, and the atlas index is `first_index + N`.
- `legend`: one character → a tile name, or `null` for no tile. Every character used in a zone layer must be a
  legend key, `null` ones included.
- The atlas is always the asset `TS_ATLAS`: 16×16 cells, numbered row by row (columns = atlas width / 16).
  Indexes go up to 254 (255 means empty).
- An `"atlas"` key appears in the example games; the engine ignores it.
- A game that only uses painted backgrounds can map every character to `null`.

### Zone files: zones/&lt;ID&gt;.json

The zone ID is the file name and must be at most 7 characters.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `size` | [w, h] tiles | required | Validator: 15×10 to 255×255. |
| `name` | string | none | Location sign (top-left) and arrival card (shown 1.8 s on entry). |
| `floor` | [string] | required | `h` strings of `w` characters. Drawn as tiles when there is no `bg`; always the source of collision. |
| `wall_back` | [string] | none | Tile layer over `floor`, only drawn without `bg`. |
| `front` | [string] | none | Tile layer drawn over characters, always (also with `bg`). |
| `solid` | string | `"#"` | Characters of the `floor` layer that are solid. |
| `bg` | asset ID | none | Painted background drawn at world (0, 0); make it `w·16 × h·16` px. When the asset exists it replaces the `floor` and `wall_back` tiles. |
| `foreground` | any | none | When the key is present, the asset `FG_<zone ID>` is drawn over the characters. Its value is not read. |
| `occluders` | [[x, y, w, h]] px | none | Only with `bg`: parts of the background redrawn over the player when the player stands behind them. |
| `blocks` | list | none | Extra solid rectangles in px: `[x, y, w, h]`, or `{"rect": [x, y, w, h], "if": cond}` (solid only while the condition holds). |
| `spawns` | object | required | `{name: [tx, ty, dir]}`. `safe` is required. |
| `exits` | list | none | See below. |
| `props`, `hotspots`, `npcs`, `fx` | lists | none | See below. |
| `shade` | [[cond, n]] | none | The first entry whose condition holds halves the brightness `n` times (everything drawn before `fx`). |
| `ambient` | ID or [{if, id}] | none | Looping ambience (mono WAV): a plain ID, or the first rule whose `if` holds. |
| `steps` | sound ID | none | Footstep sound, played on walk frames 0 and 2. |
| `exterior` | bool | `false` | With the flag `time_segment` = 1, a dusk tint (section 19). |
| `no_player` | bool | `false` | The player is not drawn (a scene without them, or seated inside a machine). |
| `on_enter` | effects | none | Run every time the zone is entered, including when a save is loaded there. |

**HD zones.** When the `bg` has a twin `<bg>_HD` (a picture twice its size, usually packed), the screen shows that
picture at full resolution and the world doubled over it. With `"hd_sprites": true` in `game.json`, a sprite, prop or
NPC whose `<sprite>_HD` exists is drawn at full resolution too:
- Its anchor is in screen pixels, and its frames are laid out as the world sprite's.
- Klaus's walk may have more frames per direction, which play faster.
- It is lit as the world (`shade`, dusk).
- The parts of the HD background that must cover it are drawn over it again at full resolution: the `occluders`, and
  each `foreground` polygon (`[[x, y], ...]` in world px). `FG_<zone ID>` is then not used.
- Sprites without an HD twin are still drawn into the world.
- Bigger neighbours need Klaus to stop further off: `"npc_foot": [x, y, w, h]` in `game.json` (world px around a
  neighbour's feet; default `[-8, -6, 16, 9]`) is the box he cannot enter, and `"npc_reach"` (default 20) how far
  he can talk to one from.

Entering a zone: sets `visited:<ID>`, updates music and ambience, runs `on_enter`, autosaves (when entered
through an exit or a `zone` effect and no sequence is running) and shows the arrival card.

### Collision

Solid for the player's feet box:

1. `floor` cells whose character is in `solid`, and everything outside the zone;
2. `blocks`;
3. visible props with `foot`;
4. visible NPCs: a fixed 16×9 px box starting 8 px left and 6 px above their anchor.

Hotspots never block. The player slides around corners by up to 5 px.

### Spawns

`"spawns": {"start": [7, 7, "N"], "from_plaza": [7, 8, "N"], "safe": [8, 6, "S"]}`. Position is the anchor of
tile `[tx, ty]`; the optional third element is the facing (default south). `safe` is the fallback for unknown
spawn names, for a save whose `content_version` changed, and for a saved position that became blocked.

### Exits

```json
"exits": [
  {"rect": [0, 4, 1, 1], "to": "Z02", "spawn": "from_casa"},
  {"rect": [7, 9, 2, 1], "to": "Z03", "spawn": "from_casa", "if": "box_open",
   "else": [["dlg", "D_CASA.exit_blocked"]]}
]
```

| Key | Meaning |
|---|---|
| `rect` | `[tx, ty, w, h]` in tiles |
| `to` | target zone (must be in `game.json` `zones`) |
| `spawn` | spawn in the target zone, default `"safe"` (validator: must exist) |
| `if` | condition; when false the exit doesn't work |
| `else` | effects run when the player walks into a closed exit (once, again only after stepping off it) |

An exit fires when the feet box enters its rect. After arriving in a zone, exits are ignored until the player
has stepped off every exit, so a spawn inside an exit doesn't bounce.

### Props

Drawn objects. Props are never interaction targets: put a hotspot on the same spot for that.

```json
{"id": "shelf", "sprite": "PR_SHELF", "at": [12, 3], "at_if": [["shelf_moved", [11, 3]]],
 "foot": [-12, -6, 24, 8]}
{"id": "box", "sprite": "PR_BOX", "at": [11, 4], "off": [8, 12], "layer": "top", "frame_if": [["box_open", 2]]}
{"id": "lantern", "sprite": "PR_LANTERN", "at": [3, 2], "anim": true, "phase": 250, "if": "!power_cut"}
```

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Target for the `move_prop` and `prop_frame` sequence steps. |
| `sprite` | asset ID | |
| `at` | [tx, ty] | Position (anchor of that tile). |
| `off` | [dx, dy] px | Added to the position. |
| `at_if` | [[cond, [tx, ty]]] | The first entry whose condition holds replaces `at`. |
| `if` | condition | Visible (drawn and solid) only while it holds. |
| `layer` | string | Absent: sorted by depth with characters. `"low"`: under everything. `"top"`: over characters, under the foreground (small things on painted furniture). `"front"`: over the foreground and `front` tiles. `"lit"`: last, over `shade` and `fx`. Any other value: never drawn. |
| `frame` | int | Static frame, default 0. |
| `frame_if` | [[cond, frame]] | The first entry whose condition holds picks the frame. |
| `anim` | bool | Loops all frames at the asset's `frame_ms` (250 ms if 0). |
| `phase` | ms | Time offset for `anim`. |
| `lift` | [dx, dy] px | Moves only the drawing (not depth, collision or position). |
| `foot` | [dx, dy, w, h] px | Solid rectangle relative to the anchor. |

### Hotspots and NPCs

Interaction targets. A target needs `dlg` or `do`, must be visible, and the player's feet must be within
`reach` px of its anchor. The nearest target is picked, with a preference for those in front of the player; C
cycles between targets in reach.

```json
"hotspots": [
  {"id": "blocked", "name": "Walled-up door", "at": [12, 2], "off": [7, 6], "reach": 26, "dlg": "D_CASA.blocked",
   "use": {"IT_KEY": "@The key needs a lock. This is just wall.", "*": "D_CASA.use_default"}},
  {"id": "door", "name": "Door", "verb": "Enter", "at": [7, 4], "do": [["sfx", "SFX_DOOR"], ["zone", "M02", "from_street"]]}
],
"npcs": [
  {"id": "baker", "name": "Baker", "sprite": "NPC_BAKER", "at": [8, 4], "facing": "S", "dlg": "D_BAKER", "reach": 52,
   "pose_if": [["!oven_lit", "NPC_BAKER_WORK"]]}
]
```

| Key | Hotspot | NPC | Meaning |
|---|---|---|---|
| `id` | yes | yes | Used by scripts (`go`, `interact`), sequences (`move_prop`) and the NPC talk gesture. |
| `at`, `off`, `at_if`, `if` | yes | yes | As for props. |
| `name` | yes | yes | Shown in the action prompt "A <verb> <name>". |
| `verb` | yes | yes | Default "Examinar" (hotspot) or "Hablar" (NPC). |
| `reach` | yes | yes | Interaction distance in px, default 20. |
| `dlg` | yes | yes | Dialogue reference opened on A. |
| `do` | yes | yes | Effects run on A, after opening `dlg`. |
| `use` | yes | no | `{ITEM: dialogue ref, "*": dialogue ref}` for "Usar" from the bag. |
| `sprite` | no | yes | NPC sheet (section 14). Hotspots are never drawn. |
| `facing` | no | yes | Default direction, default `"S"`. |
| `pose_if` | no | yes | `[[cond, SPRITE_ID]]`: while not talking, the first matching sprite replaces the normal one, all its frames looped at its `frame_ms` (400 ms if 0). |

NPC behaviour: they turn to face the player within 48 px. While a dialogue line's speaker ID equals the NPC's `id`
(case-insensitive) and the NPC faces south, it alternates frames 8 and 4 (a talking gesture). When a sequence
moves an NPC with `move_prop` and `<sprite>_WALK` exists, that sheet is used for the walk.

Items from the bag: "Usar" on a hotspot opens `use[ITEM]` or `use["*"]`; "Usar" or "Mostrar" on an NPC opens the
node `show[ITEM]` or `show["*"]` of the NPC's dialogue file (section 6). Otherwise the player says a built-in
Spanish line (section 19). During the dialogue that follows, `["using", ITEM]` is true.

### fx

```json
"fx": [{"sprite": "FX_DUST", "at": [5, 4], "phase": 120, "if": "!dust_settled"}]
```

Looping ambient sprites (`sprite`, `at`, `off`, `at_if`, `if`, `phase`), drawn after `shade`, so they are not
darkened. Frames advance at the asset's `frame_ms` (250 ms if 0).

### Draw order

1. ink fill; `bg` if the asset exists, else `floor` then `wall_back` tiles;
2. props with `"layer": "low"`;
3. props without a layer, NPCs and the player, sorted by anchor y (player skipped with `no_player`);
4. `occluders` (only with `bg`);
5. props with `"layer": "top"`;
6. `FG_<zone ID>` when the zone has `foreground`;
7. `front` tiles;
8. props with `"layer": "front"`;
9. `shade`;
10. `fx`;
11. props with `"layer": "lit"`;
12. dusk tint (exterior zones with `time_segment` = 1).

---

## 6. Dialogues

File `dialogues/<D_ID>.json`. References elsewhere in the data:

| Form | Opens |
|---|---|
| `"D_X"` | the first `entry` whose `if` holds (nothing if none does) |
| `"D_X.node"` | that node |
| `"@text"` | a one-off line said by the player |

```json
{
  "entry": [
    {"if": "!seen:D_BAKER.intro", "node": "intro"},
    {"node": "again"}
  ],
  "show": {"IT_PHOTO": "t_photo", "*": "show_default"},
  "nodes": {
    "intro": {"lines": [["BAKER:happy", "Look who's back."], ["HERO", "Just passing through."]], "next": "offer"},
    "offer": {"do": [["set", "bread_status", "offered"]],
              "lines": [{"s": "BAKER", "t": "Can you take this parcel to the bar?", "pause": 1500}],
              "choices": [
                {"id": "accept", "text": "I'll take it.", "do": [["event", "EV_BREAD_ACCEPT"]], "next": "thanks"},
                {"id": "later", "text": "Not now.", "next": "later", "repeat": "later_again"},
                {"id": "bye", "label": "Leave", "end": true}
              ]},
    "again": {"lines": [{"sub": "The oven ticks.", "if": "oven_lit"}, ["BAKER", "Anything else?"]], "next": "offer"},
    "thanks": {"lines": [["BAKER", "Thanks."]]},
    "later": {"lines": [["BAKER", "Suit yourself."]]},
    "later_again": {"lines": [["BAKER", "Still not now?"]]},
    "t_photo": {"lines": [["BAKER:worried", "Where did you find that?"]]},
    "show_default": {"lines": [["BAKER", "Hm."]]}
  }
}
```

### Nodes

| Key | Meaning |
|---|---|
| `lines` | Lines shown in order; object lines whose `if` is false are skipped. |
| `choices` | Shown after the lines. |
| `next` | Node entered after the lines when there are no visible choices. Without it the dialogue closes. |
| `repeat` | If this node was already seen, this other node is entered instead. |
| `do` | Effects run when the node is entered, before its first line. |

Entering a node sets `seen:<D_ID>.<node>`. Validator: a node needs at least one of `lines`, `choices`, `next`,
`do`; `next`/`repeat` targets must exist.

### Lines

| Form | Meaning |
|---|---|
| `["SPEAKER", "text"]` | A line. `"SPEAKER:expression"` picks the portrait frame. |
| `{"s": "SPEAKER", "t": "text", "if": cond, "do": effects, "pause": ms}` | Conditional line; `do` runs when it appears (not checked by the validator); `pause` leaves `ms` of silence, box hidden, before the next line (A cuts it short). |
| `{"sub": "text", "if": cond, "do": effects}` | Sound subtitle (labelled "Sonido"). |

The box shows 3 lines per page; text wraps by itself, and `\n` forces a break. Text types at 60 characters per
second; A completes the page, then advances.

### Choices

| Key | Meaning |
|---|---|
| `id` | Sets `topic:<D_ID>.<id>` when picked. Required with `once` or `repeat`. |
| `text` | Row text, also spoken by the player before moving on. |
| `label` | Row text when there is no `text` (nothing is spoken). |
| `silent` | `true`: show `text` but don't speak it. |
| `if` | Shown only while it holds. |
| `once` | `true`: hidden after being picked once. |
| `next` | Node to go to. Without `next` (and without `end`) the dialogue closes. |
| `repeat` | Node to go to instead of `next` when this choice was picked before. |
| `do` | Effects. Run after the spoken text; then the target node is entered, unless the effects opened another dialogue or line. |
| `end` | `true`: close the dialogue, then run `do`. B also picks it. |
| `bye` | `true`: B picks this choice. |

Up to 16 choices are shown; each wraps to at most 2 lines (the validator doesn't check choice length).

### show

`{"ITEM": "node", "*": "node"}`: the node opened when the player uses or shows that item to an NPC whose `dlg` is
this file. Keys must be items or `"*"`.

---

## 7. Sequences

`sequences.json`: `{SEQ_ID: [steps]}`, or `{SEQ_ID: {"steps": [...], "skip": [effects]}}` for a skippable scene
(C shows "Omitir"; skipping runs `skip` instead of the remaining steps).

```json
"SEQ_DESCEND": [
  ["walk", 24, 4, "HE_DESCEND", 400],
  ["walk", 72, 52, "HE_DESCEND", 1100, 22],
  ["audio_fade", 500], ["music", "MUS_UNDER"],
  ["voice", "VO_ECHO_01"], ["line", "ECHO", "A town doesn't sink all at once."],
  ["fade_out", 900], ["do", [["set", "descent_done"]]], ["save"], ["end"]
]
```

| Step | Arguments | Does |
|---|---|---|
| `wait` | ms | Waits. |
| `line` | speaker, text | Shows a line (`"SUB"` for a sound subtitle). The sequence resumes when it is read. |
| `do` | effects | Runs effects. |
| `anim` | SPRITE, ms | Plays a player animation for `ms` (4-direction sheet, section 14). |
| `walk` | dx, dy, [SPRITE], ms, [sink] | Moves the player by (dx, dy) px over `ms`, ignoring collision. SPRITE `""` or absent = the walk sheet. `sink` hides that many px of the feet progressively (going down stairs). |
| `walk_to` | x, y, [SPRITE], ms, [sink] | The same, to absolute world px. |
| `move_prop` | id, dx, dy, ms | Animates the object with that `id` (prop, NPC or hotspot) from (current position − (dx, dy)) to its current position. Move it first (an `at_if` flag set before the sequence), then animate. |
| `prop_frame` | id, frame, ms | Shows that frame of the prop for `ms`. |
| `camera` | x, y, ms | Tweens the camera offset to (x, y) px. The offset is cleared when the sequence ends. |
| `fade_out` | ms | Fades to black. The black stays until `fade_in`, another sequence or a screen reset. |
| `fade_in` | ms | Fades back in. |
| `audio_fade` | ms | Fades the ambience out until the next zone change, then waits `ms`. |
| `sfx` | ID | Sound effect. |
| `voice` | ID | Streamed one-shot. |
| `music` | CUE | Forces a cue until the next zone change (tension 3). |
| `save` | none | Writes the `auto` slot. |
| `checkpoint` | none | Writes the `prefinal` slot. |
| `end` | none | Ends the sequence and shows the end screen. |

Rules:

- Steps with no duration run in the same tick; the first timed step blocks.
- When a step puts something on top (a `line`, or a `do` that opens a dialogue, puzzle, listening point or
  arena), the sequence waits for it to close. If that step was the last one, the sequence ends there.
- While a sequence is running, another `seq` effect is ignored (logged).
- The player has no control during a sequence; the arrival autosave is skipped.

---

## 8. Items

`items.json`: `{IT_ID: item}`. Item order in the file is the order in the bag, six to a page (up to 24 carried).

```json
"IT_PHOTO": {"name": "Photo", "icon": "IC_PHOTO", "ill": "ILL_PHOTO",
             "desc": "The fountain is still there. But there's a street behind it I don't recognise.",
             "inspect": [["event", "EV_PHOTO_READ"]]}
```

| Key | Meaning |
|---|---|
| `name` | Bold heading in the bag. |
| `desc` | Description in the bag; also said by the player on "Inspeccionar". |
| `icon` | Asset drawn 2× in a 66×66 native px slot (16×16 art fits well). |
| `ill` | Illustration drawn 2× on a card above the line when inspecting. |
| `inspect` | Effects run on "Inspeccionar", before the description line. |

The bag exists only while at least one item is carried; until then MENU pauses. It shows the first 6 carried
items. Options: "Inspeccionar", "Usar", "Mostrar", "Volver". Validator: `name` fits 428 native px in the large
bold font; `desc` fits 3 lines of 428 px in the regular font and 4 in the large one. The example games carry a
`persistent` key; the engine does not read it.

---

## 9. Notebook

`notebook.json`. The notebook exists when the file has at least one top-level key (`{}` = no notebook icon, no
pause option).

```json
{
  "entries": {
    "N01": {"kind": "obs", "title": "Inheritance", "text": "They left me a key, a map, a stone and a photo."},
    "Q01": {"kind": "q", "title": "Names", "text": "Who scratched out the names?"}
  },
  "questions": [{"if": "!box_open", "t": "Question: what did they leave me?"}],
  "tasks": [{"if": ["and", "c2_started", "!street_seen"], "t": "Find where the stairs lead"}],
  "actions": [{"if": "photo_examined", "label": "Compare photo and map", "do": [["puzzle", "P01"]]}]
}
```

| Key | Meaning |
|---|---|
| `entries` | `{ID: {kind, title, text}}`; shown once `note:ID` is set, in file order (up to 64; the list scrolls). `kind` is `obs`, `test`, `heard` or `q`, labelled "Observación", "Testimonio", "Oí", "Pregunta". Validator: `kind`, `title` and `text` required. |
| `questions` | `[{if, t}]`: the first one whose `if` holds is shown at the top in bold. |
| `tasks` | `[{if, t}]`: every one whose `if` holds is listed. |
| `actions` | `[{if, label, do}]`: up to 4 buttons; picking one closes the notebook and runs `do`. |

---

## 10. Listening points

`listen.json`: `{L_ID: point}`, started with `["listen", "L_ID"]`. The player takes the listen pose, the world
is muffled (`duck.listen` in music.json) and subtitles appear over time.

```json
"L01": {"audio": "L_BAR", "max_ms": 4500, "kind": "fisico",
        "cues": [[0, "sub", "Three muffled knocks, somewhere under the wall."], [1200, "pulse"], [1700, "pulse"]],
        "do": [["set", "crack_heard"], ["note", "N04"]], "after": "D_BAR.after_listen"}
```

| Key | Default | Meaning |
|---|---|---|
| `audio` | none | Mono WAV played as a voice. |
| `max_ms` | 6000 | Duration. B stops it early. |
| `cues` | none | `[ms, "sub", text]` shows a subtitle (replacing the previous one); `[ms, "pulse"]` draws a ripple, so the rhythm reads without sound. |
| `do` | none | Effects run when it ends, finished or interrupted. |
| `after` | none | Dialogue reference opened after `do`. |
| `kind` | none | `fisico`, `eco` or `familiar`: plate label "Sonido real", "Eco", "Familiar ?" (none: "Sonido") and colour. |
| `label` | none | Replaces that plate label. |
| `level` | 0 | 1 to 3 draws signal-strength bars on the plate. |

The listening plate uses the asset `FX_LISTEN` (native size, frames looped every 200 ms).

---

## 11. Puzzles

`puzzles.json`: `{P_ID: puzzle}`, opened with `["puzzle", "P_ID"]`. The `"type"` key picks the kind. Every type
shows its `title` and shows messages in a two-line panel. `["open", "P_ID"]` is true while it is on screen. The
validator checks that every message fits the panel (section 16).

| Type | What it is | When `do` runs |
|---|---|---|
| absent | Place a translucent tracing over a plan (built for the first game, see quirks) | the moment it is solved |
| `"pattern"` | Repeat a three-step pattern (short/long pulses, or symbols) | when the player closes it solved |
| `"drill"` | Timed button exercises over the zone | when every step is done |
| `"conduit"` | Turn elbow pieces until the signal goes through | when the player closes it solved |
| `"order"` | Put up to 4 cards in order | when the player closes it solved |

An unknown `type` is treated as the default type.

### Default type (photo over plan)

Coordinates in native px. A drags (touch) or the D-pad moves the tracing 3 px a tick; A rotates it a quarter
turn; C shows the next help line; B leaves. The match is checked when the tracing is released.

```json
"P01": {"title": "The missing street", "photo": "DOC_PHOTO", "photo_card": [16, 48, 216, 144],
        "plan": "DOC_PLAN", "area": [248, 40, 216, 176], "trace": "DOC_TRACE", "trace_size": [72, 100],
        "trace_start": [262, 96, 1], "tol": 10, "solution": {"x": 325, "y": 65, "rot": 0},
        "anchors": [{"id": "fountain", "trace": [12, 66], "plan": [89, 91]},
                    {"id": "corner", "trace": [63, 92], "plan": [140, 117]}],
        "street": [[92, 97], [110, 112], [128, 124]],
        "instruction": "Match the fountain and the corner. Drag and turn the photo.",
        "partial": {"fountain": "The fountain matches. The corner is still off.", "*": "Something fits, not all."},
        "help": ["Look for something both documents show.", "The fountain is a good reference."],
        "solved_text": "The old street ran past the house.", "do": [["event", "EV_P01_SOLVE"]], "after": "D_PUZZLE.solved"}
```

| Key | Meaning |
|---|---|
| `photo`, `photo_card` | Asset drawn on a paper card at `[x, y, w, h]`. |
| `plan`, `area` | Asset drawn at `area` `[x, y, w, h]`; the tracing's centre is kept inside the area. |
| `trace`, `trace_size` | The movable asset (drawn at 50 % over the plan) and its `[w, h]`. |
| `trace_start` | `[x, y, rot]` the first time it opens. |
| `anchors` | `[{id, trace: [u, v], plan: [x, y]}]`: a point of the tracing and the plan point it must land on (plan point relative to `area`). |
| `tol` | Match distance in px, default 12. |
| `solution` | `{x, y, rot}`; on success the tracing snaps to it. Validator: it must satisfy every anchor. |
| `street` | Polyline of plan points drawn when solved. |
| `instruction`, `solved_text` | Messages. |
| `partial` | `{anchor_id: text, "*": text}`: message when only some anchors match. |
| `help` | Lines shown one by one with C; from the third, the first anchor is framed on the plan. |
| `do`, `after` | Effects on solving; dialogue opened when the solved puzzle is closed. |

### pattern

Three slots; A on a slot cycles its value. Buttons: [0] plays the slots and checks them (default "Tocar"),
[1] replays the clue (default "Oír"), [2] after `assist_after` tries fills in the answer (default "Repetir lo
oído"). C also replays the clue; B leaves, keeping what was placed. The check is symbolic, never timing.

```json
"P03": {"type": "pattern", "title": "The bell", "art": "PR_BELL",
        "solution": ["short", "short", "long"], "sfx_short": "SFX_BELL", "sfx_long": "SFX_BELL_LONG",
        "clue": "L13_BELL", "clue_text": "Two short notes. A pause. A longer, lower one.",
        "instruction": "Pick each strike with A (short or long) and press Ring.",
        "incomplete": "Some strikes are missing.", "wrong": "Nothing answers.",
        "assist_text": "If you don't remember, the third button rings it for you.",
        "solved_text": "The bell hums by itself.", "assist_after": 3, "do": [["event", "EV_NODE"]]}
```

| Key | Default | Meaning |
|---|---|---|
| `solution` | required | 3 entries. Without `symbols`: `"short"`/`"long"` (validator: must start with `s` or `l`). With `symbols`: entries of `symbols`. |
| `sfx_short`, `sfx_long` | required without `symbols` | Sounds of each pulse. |
| `symbols` | none | Names the slots cycle through instead of short/long. |
| `labels` | the symbol names | Text under each slot, per symbol. |
| `icons` | none | Asset per symbol, drawn 2× (frame 1, if any, when lit). |
| `sfx` | none | With `symbols`: the one sound every slot plays. |
| `buttons` | Spanish defaults | Labels of the three buttons. |
| `clue`, `clue_text` | `clue` required without `symbols` | Voice played and message shown by "hear again". |
| `instruction`, `incomplete`, `wrong`, `solved_text` | none | Messages. |
| `assist_after`, `assist_text` | 3, none | Tries before the fill-in button appears; message shown on that try. |
| `tries_flag` | none | Flag that keeps the try count across visits and saves. |
| `hint_after`, `hint_flag`, `hint_text` | 0 (off) | After that many tries the first slot is pre-filled with the right value and stays so (kept in `hint_flag`); `hint_text` shows on that try. |
| `clear_on_wrong`, `sfx_wrong` | `false` | Empty the slots after a wrong full answer, with that sound. |
| `slot_gap` | 20 | Native px between slots (wider for named symbols). |
| `art` | none | Illustration above the slots, drawn 2× (frame 1 while a pulse sounds). |

### drill

Steps played one at a time over the zone, timed in ticks, no damage, no overall timer. A failed step repeats
alone. B leaves (unless `stay`); progress can be kept with `step_flag`.

```json
"T02": {"type": "drill", "title": "Training", "player_anim": "SU_GUARD", "assist_after": 3, "assist_pct": 200,
        "steps": [
          {"kind": "press", "text": "Press A when the guard opens.", "lead": 70, "window": 18, "sfx": "SFX_BAK"},
          {"kind": "hold", "text": "Hold DOWN while the slow blow lands.", "lead": 60, "window": 40},
          {"kind": "rhythm", "text": "Listen, then repeat with A.", "pulses": [0, 20, 40, 70], "sfx": "SFX_KNOCK"}
        ],
        "do": [["event", "EV_TRAINING_DONE"]]}
```

| Step kind | Rule |
|---|---|
| `press` (default) | A window opens at tick `lead` and lasts `window` ticks; A inside it passes, A before it is "early", no A is "late". |
| `hold` | DOWN must be held on every tick of the window; letting go fails ("released"). |
| `rhythm` | The pulses are played (`sfx` on each), then the player repeats them with A. The first A sets the origin; each later A must land within `tol` ticks of its pulse offset. `pulses` are tick offsets, the first one 0; 2 to 6 of them (validator). C before the first A replays the demonstration. |

| Step key | Default | Meaning |
|---|---|---|
| `kind` | `"press"` | as above |
| `text` | none | Message (panel). |
| `lead` | 60 | Ticks before the window opens. |
| `window` | 24 | Window length in ticks. |
| `tol` | 18 | Rhythm tolerance in ticks. |
| `guided_tol` | 40 | Rhythm tolerance in guided mode. |
| `pulses` | none | Rhythm offsets in ticks. |
| `sfx` | none | Played when the window opens (press, hold) or on each demonstrated pulse (rhythm). |
| `ready` | `lead` for each | Tick at which each of the two `indicators` lights; the window opens with the last. |

| Drill key | Default | Meaning |
|---|---|---|
| `steps` | required | Non-empty. |
| `assist_after`, `assist_pct` | 3, 200 | After that many failures on the current step, windows and tolerances grow to `assist_pct` %. The count restarts after each passed step. |
| `guided_after` | 4 | After that many failures on the current step: a rhythm only asks for each A near its shown pulse; a press waits for A with its window open. |
| `tries_flag` | none | Keeps the failure count across visits. |
| `step_flag` | none | Number of steps done; set (with an autosave) as each step passes, so leaving or a power cut resumes there. |
| `player_anim` | none | Player animation while the drill is open. |
| `stay` | `false` | `true`: B does nothing (no way out but through). |
| `help` | none | C restarts a press/hold step and shows this message. |
| `indicators` | none | Two lamps `[[on, off], [on, off]]` (words for each state) stacked top-left; lit by each step's `ready`. |
| `title` | `""` | Header, shown as "<title> n/N". |
| `good`, `early`, `late`, `released`, `your_turn`, `cue_press`, `cue_hold` | Spanish defaults | Verdicts and prompts. |

### conduit

1 to 4 elbow pieces on a grid; A turns the selected piece a quarter clockwise; the D-pad selects. The signal lights
every piece it reaches from the input. Orientations: 0 = N–E, 1 = E–S, 2 = S–W, 3 = W–N.

```json
"P21": {"type": "conduit", "title": "Rebuild the conductor",
        "pieces": [{"at": [0, 0], "start": 0}, {"at": [0, 1], "start": 2}, {"at": [1, 1], "start": 1}],
        "in": {"at": [0, 0], "side": "W", "label": "INPUT"}, "out": {"at": [1, 1], "side": "S", "label": "ANTENNA"},
        "state_flags": ["p21_c1", "p21_c2", "p21_c3"],
        "instruction": "D-pad: pick an elbow. A: turn it.", "hint_after": 6, "hint_text": "Follow the notches.",
        "assist_after": 12, "assist_text": "C: show the right turns.", "assist_button": "Show",
        "solved_text": "Continuity restored.", "sfx_turn": "SFX_TURN", "sfx": "SFX_CONTINUITY",
        "do": [["event", "EV_RESTORE_CONDUCTOR"]]}
```

| Key | Default | Meaning |
|---|---|---|
| `pieces` | required | `[{at: [col, row], start: 0..3}]`, 1 to 4 pieces. Validator: exactly one set of orientations completes the route. |
| `in`, `out` | required | `{at: [col, row], side: "N"/"E"/"S"/"W", label}`; labels default "ENTRADA"/"SALIDA". |
| `state_flags` | none | One flag per piece, value orientation + 1: turns survive leaving and saves. |
| `hint_after`, `hint_text` | 6 | Turns without progress before the hint. |
| `assist_after`, `assist_text`, `assist_button` | 12, none, "Mostrar" | After that many turns without progress, C sets every piece right. |
| `sfx_turn`, `sfx` | none | Sound per turn; sound on completion. |
| `instruction`, `solved_text` | none | Messages. |

### order

Cards in slots; A takes a card and A on another slot swaps them; a confirm button checks the order and frames
the cards out of place. B drops a taken card, or leaves keeping the order.

```json
"P22": {"type": "order", "title": "Order the signal",
        "cards": [{"text": "Containment holds.", "mark": "01"}, {"text": "We need help.", "mark": "02"},
                  {"text": "If anyone is listening…", "mark": "03"}],
        "start": [2, 0, 1], "state_flags": ["p22_s1", "p22_s2", "p22_s3"], "tries_flag": "tries_p22",
        "instruction": "A: take a card and place it. Confirm when they are in order.",
        "wrong": "Some fragments are out of order: they are marked.", "assist_after": 2,
        "assist_text": "The second button sorts them by their marks.", "solved_text": "Message rebuilt.",
        "do": [["puzzle", "P22R"]]}
```

| Key | Default | Meaning |
|---|---|---|
| `cards` | required | Up to 4 `{mark, text}`, listed in the correct order. Validator: `text` fits one row (312 native px) in both fonts. |
| `start` | identity | Card index shown in each slot at first. |
| `state_flags` | none | One flag per slot, value card index + 1. |
| `tries_flag` | none | Keeps the wrong-confirm count. |
| `assist_after`, `assist_text` | 2, none | Wrong confirms before the "sort by marks" button appears. |
| `buttons` | "Confirmar", "Ordenar por las marcas" | Labels of the two buttons. |
| `instruction`, `wrong`, `solved_text` | none | Messages. |

---

## 12. Arena (side-view fights)

`arena.json` (optional): `{A_ID: arena}`, started with `["arena", "A_ID"]` (or `["arena", "A_ID", "practice"]`).
The fight covers the zone; the player's body is always left of the boss. Distances are world px between body
centres; times are ticks.

Controls: LEFT/RIGHT walk; A attacks; DOWN guards (a hit that lands no later than `perfect_end` ticks after DOWN
was pressed is a perfect guard); B dodges back (forward with RIGHT held). Flow: the boss cycles its `phase1` list; at `phase2_hp` it
shakes (or plays its `interlude`) and cycles `phase2`; at 1 HP it is exposed (the `exposed` dialogue opens); A
breathes until resonance is 100; UP starts the Canto; three A presses in the lit window free the boss; the screen
fades and `win` runs. At 0 HP the player kneels and a menu offers retry, leave (`leave` effects) and the help
toggle (`assist_flag`). A boss is never killed.

```json
"A01": {"boss_name": "IRON BEAST", "bg": "BG_A01", "music": "MUS_ARENA",
        "intro": "D_A01.intro", "intro_flag": "boss_intro_seen", "exposed": "D_A01.exposed", "assist_flag": "help_on",
        "win": [["set", "boss_freed"], ["zone", "M06", "after_fight"], ["save"]], "leave": [["zone", "M06", "hangar"]],
        "player": {"sprite": "GG", "hp": 100, "attack": {"damage": 10, "reach": 30, "frames": [2, 2, 1]}},
        "boss": {"sprite": "BU", "hp": 160, "phase2_hp": 80, "phase1": ["charge", "pause", "bite"],
                 "phase2": ["slam", "charge", "bite"], "bite": {"tell": 54, "damage": 22, "guard": false}},
        "barks": {"bite": ["ALLY", "It doesn't stop biting. Get out of there!"]},
        "canto_barks": [["MENTOR", "Breathe."], ["ALLY", "Core stable."], ["MENTOR", "Now."]],
        "sfx": {"hit": "SFX_HIT", "block": "SFX_BLOCK", "hurt": "SFX_HURT", "tell_bite": "SFX_JAW"}}
```

### Top-level keys

| Key | Default | Meaning |
|---|---|---|
| `bg` | none | 240×160 background (ink fill if missing). |
| `floor_y` | 126 | Feet line in px. |
| `min_x`, `max_x` | 12, 228 | Arena edges in px; the floor is split into three equal sectors between them. |
| `music` | none | Cue forced during the fight (the ambience is hushed). |
| `sfx` | none | `{event: sound ID}` (list below). |
| `intro` | none | Dialogue opened when the fight starts. |
| `intro_flag` | none | With it, `intro` plays only once (retries skip it). |
| `intro_spit` | none | `{sprite}`: an object thrown from the boss before `intro` (frame 0 in flight, 1 on the ground). |
| `exposed` | none | Dialogue opened when the boss is exposed. |
| `boss_name` | `""` | Top-right label. |
| `win`, `leave`, `practice_win` | none | Effects after winning, after "leave" from the defeat menu, after winning in practice (falls back to `leave`). Usually a `zone` effect. |
| `leave_label` | "Volver" | Defeat-menu label for leaving. |
| `assist_flag` | none | Flag toggled by the defeat menu's help option; while set, tells are longer and damage lower (`assist`). |
| `assist` | `{damage_pct: 65, tell_pct: 130}` | Assist strength. |
| `mods` | none | `[{if, hp, dodge_recover}]`: every entry whose `if` holds overrides those player values. |
| `barks` | none | `{pattern or "phase2" or "interlude": [speaker, text]}`: a hint strip shown the first time that pattern warns (or phase 2 / interlude starts), for 2 s. |
| `canto_barks` | none | Three `[speaker, text]`, one per Canto pulse. |
| `unguardable_hint` | none | Prompt shown when the player guards an unguardable attack. |
| `goals` | none | Simulation mode: subset of `"guard"`, `"hit"`, `"dodge"`, `"breath"`. When all but `breath` are done the target kneels; breathing then ends the fight. |
| `goal_labels` | the goal names | Four labels in the fixed order guard, hit, dodge, breath (not the order of `goals`). |

### player

| Key | Default | | Key | Default |
|---|---|---|---|---|
| `sprite` | `"GG"` | | `immunity` | 42 (ticks after a hit) |
| `x` | 45 | | `breaths` | 3 (A presses to fill resonance) |
| `hp` | 100 | | `canto_window` | 60 (ticks a Canto pulse stays open) |
| `half_w` | 10 | | `core` | `[3, 25]` (Canto glow point from the feet) |
| `speed` | 60 (px/s) | | `resonance` | `{hit: 10, block: 5, perfect: 15, dodge: 8, hurt: -8}` |
| `attack` | `{windup: 9, active: 6, recover: 15, damage: 10, reach: 30, frames}` | | `guard` | `{start: 3, perfect_end: 12, pct: 30, frames}` (`pct` = damage taken when guarding) |
| `dodge` | `{time: 18, move: 12, recover: 21, dist: 24, iframes: [6, 14], frames}` | | | |

### boss

| Key | Default | Meaning |
|---|---|---|
| `sprite` | `"BU"` | Sprite prefix. |
| `x`, `hp`, `phase2_hp`, `half_w`, `speed` | 185, 160, 80, 26, 60 | |
| `pause` | 40 | Ticks of a `"pause"` entry in a phase list. |
| `shake` | 30 | Ticks of the phase-2 shake. |
| `phase1`, `phase2` | none | Lists of pattern names and `"pause"`, cycled. Validator: known names only. |
| `fixed` | `false` | The boss never walks toward the player. |
| `interlude` | none | `{ticks: 360, pulses: [ticks...], label}`: instead of the shake, the boss kneels out of reach for `ticks` while floor pulses strike the player's sector at each listed tick; a bar labelled `label` counts down. |
| `repair` | none | Repair mode: `{cycles: 3, label, shield_label, barks}`. Phase 1's HP is a shield ("Protección") that only takes one blow per recovery window of the `vulnerable` pattern; when it is empty, each complete pass of `phase2` closes one of `cycles` segments ("Reparación n/N", one `barks` line each); after the last the boss is stable and `win` runs. No resonance and no Canto. Validator: needs a non-empty `phase2`. |
| `vulnerable` | none | Pattern whose recovery opens the shield in repair mode (without it, any pattern's recovery does). Validator: a pattern name, not `"pause"`. |
| `<pattern>` | see below | `{tell, active, recover, damage, reach, guard, frames}` per pattern. |

| Pattern | tell | active | recover | damage | reach | guard | Behaviour |
|---|---|---|---|---|---|---|---|
| `charge` | 45 | 30 | 54 | 18 | 60 | yes | runs `reach` px toward the player |
| `bite` | 54 | 12 | 60 | 22 | 22 | no | short range, must be dodged |
| `slam` | 60 | 12 | 69 | 20 | 40 | yes | ring around the boss |
| `shield` | 90 | 0 | 0 | 0 | 0 | yes | plate up: the player's blows do nothing |
| `sweep` | 48 | 15 | 60 | 18 | 36 | yes | low sweep |
| `pulse` | 54 | 12 | 30 | 15 | 0 | no | strikes the floor sector the player stood in |
| `marks` | 54 | 12 | 30 | 15 | 0 | no | strikes left, centre, right sectors one after another |

Damage taken = base × (`guard.pct` % when guarding) × (`assist.damage_pct` % with assist), rounded, at least 1
(0 stays 0, for simulations).

`sfx` events: `hit`, `block`, `perfect`, `dodge`, `hurt`, `shield` (a blow on the raised plate), `canto`, `free`,
`spit`, `spit_land`, `interlude`, `segment`, `stable`, `pulse` (interlude strikes), `tell_<pattern>` (warning) and
`<pattern>` (strike). Missing events are silent.

Validator (arena.json): dialogues, flags, effects, music and sounds exist; `boss_name`, `goal_labels`, repair
labels are cp1252; each bark line "Name: text" fits 2 lines of 440 native px in both fonts; `unguardable_hint`
fits one line; goal labels fit one row in the large bold font.

Arena sprites are listed in section 14.

---

## 13. Music and sound

### WAV format (audio/&lt;ID&gt;.wav)

- RIFF/WAVE, format tag 1 (PCM) or 0xFFFE (extensible), **16-bit, 22050 Hz**. The `fmt ` chunk must come
  before `data`; other chunks are skipped; `data` must hold at least one frame.
- **Mono** for everything except music cues. Music cues have 1 to 3 interleaved channels; each channel is a
  layer of the same piece, all looping together.
- IDs are at most 31 characters (validator).
- Sound effects are loaded into RAM (up to 20 s; longer ones are cut with a fade). Optional variants
  `<ID>_2`, `<ID>_3`, `<ID>_4` are picked at random, never the same twice in a row.
- Ambience, music and voices are streamed from the card.

### music.json

```json
{
  "title": {"cue": "MUS_RETURN", "tension": 1, "ambient": "AMB_PLAZA"},
  "end": {"cue": "MUS_UNDER", "tension": 1},
  "cues": {"MUS_RETURN": {"bpm": 76, "beats": 3, "loop_at": 4.5,
                          "layers": [[1, 0, 0], [1, 0.75, 0], [0.9, 1, 0.7], [0.75, 1, 1]]}},
  "zones": {"Z03": "MUS_RETURN", "Z02": [{"if": "door_open", "cue": "MUS_UNDER"}, {"if": "box_open", "cue": "MUS_HOUSE"}]},
  "tension": [{"if": "panel_open", "level": 3}, {"if": "box_open", "level": 1}],
  "zone_tension": {"Z03": -1, "Z07": 1},
  "rest": {"after_s": 150, "for_s": 45, "max_tension": 2},
  "fade": {"cue_in": 3000, "cue_out": 2500, "ambient": 1800, "hush": 700, "up_bars": 1.5, "down_bars": 3, "rest_out_bars": 4},
  "duck": {"dialogue": [0.8, 0.6, 400], "listen": [0.25, 0.2, 900, 1800], "puzzle": [0.5, 0.85, 800]},
  "sfx": {"open": ["SFX_UI_OPEN", 0.7], "move": ["SFX_UI_MOVE", 0.5], "note": "SFX_HINT", "solved": "SFX_REVEAL"},
  "events": {"Z01": [{"id": "SFX_AMB_CREAK", "every": [25, 70], "gain": 0.5, "if": "!box_open"}]}
}
```

| Key | Meaning |
|---|---|
| `title`, `end` | `{cue, tension, ambient}` for the title and end screens. Validator: both cues required and defined. |
| `cues` | `{CUE: {bpm, beats, loop_at, layers}}`. The cue ID is also the WAV ID. `bpm` × `beats` (default 4) defines a bar; layer changes and stops wait for the next bar line (without `bpm` they apply at once). `loop_at` (seconds) is where the loop restarts after the first pass (an intro). `layers`: exactly 4 rows (tension 0 to 3), each with one gain (0 to 1) per WAV channel (validator). |
| `zones` | `{ZONE: CUE}` or `{ZONE: [{if, cue}]}` (first match). A zone with no match plays no music. Keys must be zones in `game.json`. |
| `tension` | `[{if, level}]`: the first match gives the story tension. |
| `zone_tension` | `{ZONE: offset}` added to it; the result is clamped to 0..3 and picks the `layers` row. |
| `rest` | `{after_s, for_s, max_tension}`: after `after_s` seconds of the same cue at tension ≤ `max_tension` (default 1), the music fades out for `for_s` seconds (default 40); a rise in tension ends the rest early. Validator: `after_s` ≥ 10, `for_s` ≥ 1. |
| `fade` | Times in ms (or bars): `cue_in` 3000, `cue_out` 2000, `ambient` 1800, `hush` 1800, `up_bars` 1.5 (2500 ms without bpm), `down_bars` 3 (8000 ms), `rest_out_bars` 4 (6000 ms). |
| `duck` | `{none, dialogue, listen, puzzle, tell: [ambience gain, music gain, fade ms (800), ambience lowpass Hz (0 = open)]}`; `tell` applies while an arena boss warns. Missing presets mean no ducking. |
| `sfx` | Named interface sounds: `{name: ID or [ID, gain]}`. Names the engine plays: `move`, `back`, `open`, `ok`, `advance`, `note`, `solved`, `error` (falls back to `back` when undefined). |
| `events` | `{ZONE: [{id, every: [min_s, max_s], gain, if}]}`: one-shots at random intervals over the ambience, only while the player walks freely; `gain` default 0.5; up to 12 per zone. Validator: `min_s` ≥ 1, `max_s` ≥ `min_s`. |

A cue forced by the `music` effect or step plays at tension 3 until the next zone change. A new cue waits for
the old one to fade out completely before it starts.

---

## 14. Assets (runtime image format)

`uv run tools/png2asset.py image.png games/mygame/assets ID [--frames N --ms MS --anchor X,Y --type background]`
converts a PNG (one image or a horizontal strip of frames) into this format.

Each image is two or three files in `assets/`, named by its ID (at most 31 characters):

| File | Content |
|---|---|
| `<ID>.meta.json` | geometry (below) |
| `<ID>.rgb565` | pixels: RGB565, 2 bytes per pixel, **little-endian**; all frames one after another, each frame `w × h` pixels row by row. Size must be exactly `w × h × frames × 2` bytes, else a placeholder with the declared geometry is drawn. |
| `<ID>.mask` | optional transparency: 1 bit per pixel, **1 = opaque**, MSB first (bit 7 of a byte is the leftmost pixel). Each row is `stride = (w + 7) / 8` bytes; each frame is `stride × h` bytes; frames one after another. Size must be exactly `stride × h × frames`, else the asset is drawn opaque. No mask = fully opaque. |

RGB565 packing: `((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)`.

### meta.json

```json
{"w": 24, "h": 32, "frames": 8, "frame_ms": [600, 600, 600, 600, 600, 600, 600, 600], "anchor": [12, 29]}
```

| Key | Default | Meaning |
|---|---|---|
| `w`, `h` | required | 1 to 1024. |
| `frames` | 1 | 1 to 64. |
| `anchor` | `[w / 2, h − 1]` | Pixel of the image placed on the object's anchor (feet). Use `[0, 0]` for backgrounds and UI art. Read by `pinyol@1` games (the world and the arena); a `pinyol@2` game places its pictures by their top-left corner and reads nothing of it (the editor writes it from a drawing's turning point, which kit.lua takes from data.lua). |
| `frame_ms` | `[0]` | **An array**; only its first element is read, by `pinyol@1` games: ms per frame for looping animations (0 = the engine's default for that use). A plain number is ignored. `pinyol@2` games never read it: their timing is in Lua (`"anim"`, kit.lua's anims); the editor writes each frame's real length for tools. |

Any other key (the example games' files also carry `asset`, `type`, `tile`, `order`, `rgb565`, `memory_bytes`...)
is ignored by the engine.

### Packed pictures

`png2asset.py --packed [--colours N]` writes `<ID>.pk` instead of `.rgb565` and `.mask`, and `"format": "packed"`
in the meta: the picture's own palette (up to 256 colours, exact when it has no more, else reduced to `N`, 256 by
default) and each column as runs of opaque pixels, 4 bits a pixel when 16 colours are enough, 8 otherwise. A big
picture with see-through around it takes a quarter of the memory or less, and is drawn faster: the console reads
far fewer bytes, and draws its strips column by column, as the file keeps them. Mirrored, scaled, in another
palette or as one colour (`img`'s `flip_x`, `scale`, `pal`, `tint`) it is drawn straight from the runs; only
turned (`angle`) or doubled (`scale` 2 as the fifth argument) it is unpacked once, when first drawn so.

| Bytes | Content (little-endian) |
|---|---|
| 0 | `NP2K` |
| 4 | version 1; bits a pixel, 4 or 8 |
| 6 | `u16` colours (1..256), `u16` w, `u16` h, `u16` frames, `u16` 0 |
| 16 | the palette: colours × `u16` RGB565, padded to a multiple of 4 bytes |
| then | frames × w `u32`: where each column starts, from the start of the file (frame by frame, left to right) |
| a column | `u16` runs; each run `u16` y, `u16` length, then its pixels' colour numbers (4 bits: the upper half first, the last byte padded) |

The engine checks the whole file when it loads it (every column and run inside the file and the picture, every
colour number inside the palette); a file that fails is drawn as a placeholder.

### Draw scale

| Drawn at world scale (1 asset px = 2×2 screen px) | Drawn 2× on the native screen | Drawn at native size |
|---|---|---|
| zone `bg`, `FG_<zone>`, `TS_ATLAS`, player, NPC, prop and fx sprites, arena `bg` and sprites | `BG_TITLE`, item `icon` and `ill`, `UI_BAG`, `UI_BOOK`, pattern `icons` and `art` | `LOGO`, `LOGO_SMALL`, portraits, `FX_LISTEN`, objective check icons, default-puzzle `photo`/`plan`/`trace` |

### IDs the engine looks up by name

| ID | Use |
|---|---|
| `TS_ATLAS` | tile atlas |
| `BG_TITLE` | title background, 240×160 (also the console list thumbnail at that size) |
| `LOGO` | title logo |
| `LOGO_SMALL` | end-screen logo |
| `UI_BAG`, `UI_BOOK` | HUD buttons (40×40 native plates; ~16×16 art); `UI_BOOK` also heads toasts |
| `FX_LISTEN` | listening plate icon |
| `FG_<zone ID>` | zone foreground, when the zone has `foreground` |
| `<player.sprite>_IDLE`, `_WALK`, `_INTERACT`, `_LISTEN`, `_DESCEND` | player animations |
| `<ID>_B` | variant of a player sprite or the player's portrait, used when the "Bolso" option is on |
| `<npc sprite>_WALK` | NPC walking during `move_prop` (optional) |
| arena `<prefix>_<POSE>` | below |

`BG_<zone>` is only a naming convention: a zone names its background with `bg`.

### Sheet layouts

Directions are always in the order N, E, S, W.

| Sheet | Layout |
|---|---|
| player `_IDLE`, `_WALK` | 4 directions × k frames (frames / 4 per direction), looped at `frame_ms` (600 ms if 0). Footsteps play on walk frames 0 and 2, so 4 walk frames per direction fit best. |
| player `_INTERACT` | 8 frames: 2 per direction (shown for 350 ms after interacting). |
| player `_LISTEN` | 8 frames: 2 per direction (second one after 300 ms of listening). |
| player `_DESCEND` | one direction, all frames looped (used through the `walk`/`anim` steps). |
| other player animations (`anim` step, `player_anim`) | 4 directions × k frames, like `_IDLE`. |
| NPC `sprite` | frames `dir × 2` and `dir × 2 + 1` alternate every 600 ms (8 frames); frame 8 is the talking gesture (alternates with frame 4 while it speaks facing south). |
| NPC `_WALK`, `pose_if` sprites | `_WALK`: 4 directions × k frames at 125 ms; `pose_if`: one view, all frames looped. |
| portrait | one frame per entry of `expressions`. |
| props, fx | free; `anim`/`fx` loop all frames. |
| arena | one view (player faces right, boss faces left). |

Arena sprites (`<player.sprite>_` and `<boss.sprite>_` prefixes):

| Player pose | Use | Boss pose | Use |
|---|---|---|---|
| `IDLE` | looped, 400 ms | `IDLE` | looped, 500 ms |
| `WALK` | looped, 125 ms | `WALK` | approaching (optional) |
| `ATTACK` | `attack.frames` split over windup/active/recover (default 1 frame each) | `CHARGE`, `BITE`, `SLAM`, `SHIELD`, `SWEEP`, `PULSE` | pattern poses; `frames` per pattern split over tell/active/recover (default `[1, 1, 0]`, 0 = idle pose); `PULSE` also serves `marks`; optional (idle when missing) |
| `GUARD` | `guard.frames` [raising, held] | `HURT` | after a blow (optional; flicker otherwise) |
| `DODGE` | `dodge.frames` [moving, recovery] | `EXPOSED` | exposed and freed |
| `KNEEL` | defeat, played over 30 ticks | `KNEEL` | interlude (optional; `EXPOSED` otherwise) |
| `CANTO` | frame = Canto pulse (0 to 2), last frame when freed | `FREE` | release (optional) |
| `IMPACT` | just after being hit (optional) | `OPEN`, `STABLE` | repair mode: shield open, stable end (optional) |

---

## 15. Fonts (FNT1)

Four files in `fonts/`: `FONT_MAIN` (regular), `FONT_BOLD` (names, buttons, titles) and their `_L` versions used
when the player turns on "Texto grande". All four are required, and the validator measures text with them.

| Offset | Size | Content |
|---|---|---|
| 0 | 4 | `"FNT1"` |
| 4 | 1 | cell width `w` in px |
| 5 | 1 | cell height `h` in px |
| 6 | 2 | not read by the engine (`ttf2fnt.py` writes the ascent and 0) |
| 8 | 256 | advance width of each glyph, indexed by cp1252 code |
| 264 | 256 × h × stride | glyph bitmaps, glyph after glyph, rows of `stride = (w + 7) / 8` bytes, MSB first, 1 = ink |

The file size must be exactly `264 + 256 × h × stride`. `tools/font2fnt.py` makes one from a TTF/OTF, a BDF, a PNG
sheet or a font of `third_party/fonts`: `font2fnt.py in.ttf out.fnt [--px 11] [--scale 2] [--weight 700]
[--spacing 1]` (`ttf2fnt.py`, the old name, still works). pinyol@2 games may also have any fonts of their own,
`fonts/<name>.fnt` in the same format ([lua.md](lua.md#a-games-own-look)).

---

## 16. Text rules

- JSON files are UTF-8. Every character must be encodable in **Windows-1252**: ASCII, U+00A0–U+00FF, and
  € ‚ ƒ „ … † ‡ ˆ ‰ Š ‹ Œ Ž ‘ ’ “ ” • – — ˜ ™ š › œ ž Ÿ. Anything else is drawn as `?`; the validator reports it in
  the fields it checks.
- Wrapped text breaks at spaces; `\n` forces a break; a word wider than the line is split across lines.
- Checked for cp1252 by the validator: dialogue lines and choice `text`, `@text` references, `say` text, item
  `name` and `desc`, notebook entry `text`, question/task `t`, action `label`, sequence `line` text, listening
  subtitles, puzzle messages and labels, objectives, chapter `title` and `end_text`, arena texts.
- Not checked (keep them cp1252 yourself): game `title`/`subtitle`/`tagline`, speaker names, zone names, hotspot
  and NPC `name`/`verb`, choice `label`, notebook entry `title`, puzzle `title`, listening `label`, `bag_label`,
  button labels, end-screen labels.

Fit checks (native px, against the game's own fonts; "both fonts" = regular and large):

| Text | Must fit |
|---|---|
| puzzle messages: `instruction`, `solved_text`, `help`, `partial`, `hint_text`, `assist_text`, `wrong`, `incomplete`, `clue_text`, drill step `text` and `help` | 2 lines of 416 px, both fonts |
| item `name` | 428 px, large bold |
| item `desc` | 3 lines of 428 px (regular), 4 lines (large) |
| objective `text` | one line: width + 40 ≤ 464 px, both fonts |
| chapter `end_text` | 448 px in large bold, or each half around `" · "` |
| order card `text` | one line of 312 px, both fonts |
| drill `indicators` | the wider word of each lamp + 52 ≤ 456 px, large bold |
| arena barks (drawn as "Name: text") | 2 lines of 440 px, both fonts |
| arena `unguardable_hint` | width + 28 ≤ 472 px, bold, both sizes |
| arena `goal_labels` | 12 + Σ(width + 26) ≤ 472 px, large bold |

Dialogue lines have no length limit (they page); choices are cut after 2 lines without a warning.

---

## 17. Validation and test scripts

`pinyol_headless` is the engine's command-line runner (CMake target `pinyol_headless`, no window, no sound device).

```
pinyol_headless --game DIR [--saves DIR] [--fresh] (--validate | --script FILE) [--strict-assets] [--audio FILE.pcm] [--video FILE.mp4]
```

| Option | Meaning |
|---|---|
| `--game DIR` | game folder |
| `--saves DIR` | save folder (default `DIR/saves`) |
| `--fresh` | delete `*.sav` and `*.ppm` in the save folder first |
| `--validate` | run the validator |
| `--strict-assets` | draw the first frame and fail if any required picture used during validation or a test script is missing or invalid; optional picture lookups are allowed |
| `--script FILE` | run a test script (after validation, if both are given and validation passed) |
| `--audio FILE.pcm` | dump the mix as raw PCM16 mono at 22050 Hz |
| `--video FILE.mp4` | record the run at 30 fps through `ffmpeg` |

Exit code: 0 pass; 1 validation errors or a failed script; 2 bad arguments, an incomplete game folder (missing
JSON or fonts) or an unreadable script. Validator output is one line per problem,
`validate: <where>: <message>`, then `validate: N error(s)`. Scripts print `PASS <file>` or
`FAIL <file>:<line>: <command> <args> -> <reason>`.

The desktop simulator `pinyol_sim --game DIR [--saves DIR] [--scale N] [--mute] [--script FILE]` (needs SDL2) plays the
same folder. Keys: arrows/WASD move, Enter/E/Space = A, Esc/Backspace = B, Tab/C = C, I = MENU, J = notebook,
P = START; the mouse is touch.

### Script language

One command per line, `command arguments`. `#` starts a comment at the start of a line or after a space. The
script starts on the title screen and feeds input through the real game loop, 60 ticks a second. While the game
is being played, every tick checks the `events.json` invariants; a broken one fails the script.

Keys: `UP`, `DOWN`, `LEFT`, `RIGHT`, `A` (= `OK`), `B` (= `BACK`), `C` (= `NEXT`), `MENU` (= `INV`), `NOTES`,
`START` (= `PAUSE`); combine with `+` (`DOWN+A`).

| Command | Does |
|---|---|
| `new` | New game. |
| `continue [SLOT]` | Load a slot (default: the newest save). |
| `tick N` | N idle ticks. |
| `press KEY` | Press and release (one tick each). |
| `hold KEY N` | Hold for N ticks, then release. |
| `advance` | Press A through dialogue, wait through sequences, listening and arena presentations, until the player is free or a choice is up. |
| `choose X` | Pick the choice whose `id` is X or whose text contains X. |
| `go ID` | Walk (path-finding) next to the visible hotspot or NPC `ID` and target it. |
| `interact ID` | `go ID`, then A. |
| `exit ZONE` | Walk through the exit leading to ZONE. |
| `inspect ITEM`, `use ITEM`, `show ITEM` | Open the bag and do that with the item. |
| `p01 place X Y ROT`, `p01 keys X Y ROT`, `p01 solution` | Default puzzle: drag the tracing (touch) or move it with the D-pad to native x, y with a rotation; or place it near its `solution`. |
| `drill_wait PHASE [KEY or -] [MAX]` | Tick (holding KEY) until the drill phase is `lead`, `demo`, `input` or `result` (MAX default 600). |
| `arena ID` | Start a fight directly. |
| `arena_auto [MAX]` | A plain bot fights until the arena closes (MAX ticks, default 54000). |
| `arena_wait boss\|player STATE [KEY or -] [MAX]` | Tick until the state is reached (MAX default 1200). Boss states: `idle`, `wait`, `approach`, `tell`, `active`, `recover`, `shake`, `exposed`, `freed`, `interlude`, `stable`. Player states: `free`, `attack`, `guard`, `dodge`, `kneel`, `canto`. `none` without a fight. |
| `expect_arena FIELD OP N` | OP: `==`, `!=`, `<`, `>`, `<=`, `>=`. Fields: `player_hp`, `boss_hp`, `resonance`, `phase`, `gap`, `goals_left`, `max_hp`, `dodge_recover`, `hint`, `pattern` (0 charge … 6 marks), `sector`, `progress`, `bark`. |
| `arena_set FIELD N` | Debug: set `boss_hp`, `resonance` or `player_hp`. |
| `expect COND` | A condition (JSON, or a bare flag string like `!box_open`) must hold. |
| `expect_not COND` | It must not hold. |
| `expect_zone ZONE` | Current zone. |
| `expect_layer NAME` | Top screen: `TITLE`, `PLAY`, `DLG`, `INV`, `NOTES`, `PUZZLE`, `SEQ`, `LISTEN`, `PAUSE`, `END`, `ERROR`, `ARENA`. |
| `expect_text TEXT` | TEXT appears in the current line, puzzle message, listening subtitle, toast or error screen. |
| `expect_no_text TEXT` | It doesn't. |
| `expect_no_choice ID` | Choices are showing and none has that id. |
| `expect_save SLOT` | The slot holds a valid save. |
| `save [SLOT]` | Write a slot (default `manual`). |
| `powercut` | Restart the engine from the card: RAM lost, saves kept. |
| `missing_audio ID`, `missing_asset ID`, `missing_zone ID` | Pretend a file is missing (`missing_audio *` = all sound). |
| `shot NAME` | Write a screenshot `NAME.ppm` in the save folder. |
| `zone ZONE` | Debug: jump to the zone's safe spawn. |
| `flag NAME [VALUE]` | Debug: set a flag to 1, a number or an enum value name. |
| `place X Y` | Debug: put the player's feet at world px, ignoring collision. |
| `pace N` | From now on, N idle ticks after every press. |
| `read CPS` | From now on, `advance` waits as long as reading each line takes at CPS characters per second, and `choose` waits 2 s. |
| `log TEXT` | Print TEXT. |
| `mute` | No effect. |

A script for the minimal game of section 1:

```
# read the sign twice, save, cut the power, resume
new
advance
expect_layer PLAY
interact sign
expect_text welcome
advance
expect sign_read
expect ["seen", "D_SIGN.first"]
interact sign
expect_text Still says
advance
save
powercut
expect_layer TITLE
continue
expect_zone Z01
expect sign_read
```

---

## 18. Engine limits

| Thing | Limit |
|---|---|
| Zone size | 15×10 to 255×255 tiles (validator) |
| Zone ID | 7 characters |
| Asset ID, audio ID, dialogue ID | 31 characters (longer asset IDs are truncated, so two IDs sharing their first 31 characters collide) |
| Player sprite prefix | 7 characters |
| Speaker ID including `:expression` | 23 characters |
| Object `id` targeted by `move_prop` / `prop_frame` | 23 characters |
| Prefixed flag name (`seen:D_X.node`...) | 95 characters |
| Flag values | 16-bit signed |
| Distinct flag names set in one session (from start-up) | 2048 (prefixed ones included) |
| Distinct assets loaded in one session | 320; the image cache never frees, later ones become placeholders |
| Image size | 1024×1024, 64 frames |
| Tiles in the atlas | 255 (indexes 0–254) |
| Depth-sorted things per zone | 63 props and NPCs plus the player |
| Targets in reach | 16 |
| Dialogue choices shown | 16 |
| One-off line (`say`, item description) | 511 bytes |
| Bag | 6 items shown |
| Notebook | 16 entries, 4 actions |
| Music layers | 3 channels per cue |
| Ambient events per zone | 12 |
| Sound effect length | 20 s (longer ones are cut) |
| Sound effect RAM | 1.5 MB, least recently played freed first |
| Effect nesting | 16 |
| Conduit pieces / order cards / pattern slots | 4 / 4 / 3 |
| Games in the console list | 4 |

---

## 19. Known quirks and current limitations

The engine grew out of two games and still carries some of their assumptions.

- **Player defaults are the first game's.** Without a `player` key the player is speaker `"KLAUS"` with sprites
  `KL_*`, the portrait falls back to `"PT_KLAUS"`, and the options offer "Bolso: mochila/bandolera", which swaps in
  `_B` art. Set `player` in every new game.
- **The `_B` variant** applies to the player's portrait and to the stair-descent drawing (`sink`); the normal
  player drawing call uses the base ID.
- **Start zone defaults to `"Z01"`** (game start, chapter start, and the zone a save without `zone=` loads), spawn
  defaults to `"safe"`. The validator does not check `start.zone`, `start.seq`, a chapter's `after.zone` or the
  spawn of a `zone` effect.
- **Built-in UI text is Spanish.** Menus ("Continuar", "Nueva partida", "Texto grande", "Retratos", "Pausa",
  "Guardar partida", "Volver al título", "Cuaderno"), bag options ("Inspeccionar", "Usar", "Mostrar", "Volver"),
  default verbs ("Hablar", "Examinar"), "Nueva nota:", "Escuchando", "B para parar", "Omitir", "Sonido", notebook
  kind labels, puzzle buttons ("Girar", "Ayuda", "Tocar", "Oír", "Confirmar"...), drill verdicts, arena menu and
  prompts ("Reintentar", "Ayuda: sí/no", "A · Respirar", "Arriba · Canto"), the end screen ("Fin", "Continuará…",
  "Seguir jugando"), error screens, and the player's fallback lines ("No sirve aquí.", "No parece interesarle.",
  "No creo que le interese.", "No hay nadie a quien enseñárselo.", "Aquí no hay nada en lo que usarlo."). Data keys
  override some of them: `verb`, `bag_label`, pattern `buttons`/`labels`, order `buttons`, conduit labels and
  `assist_button`, drill texts, listening `label`, arena `leave_label`/`goal_labels`/repair labels, chapter
  `after.label`/`load_label`, `end_text`.
- **The default puzzle type is hardwired to the first game's P01.** It refuses to open unless the player carries
  items `IT_PHOTO` and `IT_PLAN` ("Necesito la foto y el plano para compararlos."), sets the flag `p01_opened`
  itself, shows the solved state when the flag `photo_plan_linked` is set (your `do` must set it), and saves the
  tracing position in every save file.
- **Without `chapters`, or for a chapter without `done`**, the "chapter done" test is the flag
  `first_descent_complete`.
- **End-screen label bug:** when a next chapter exists and "Continuar: <title>" fits, the first option is
  relabelled with the finished chapter's `after.label` ("Seguir jugando" if `after` has no label) or, without
  `after`, "Continuará…". The option still starts the next chapter. A title long enough not to fit shows
  "Continuar" instead.
- `["open", ID]` stays true after a default-type puzzle is closed, until another puzzle opens or a new game or
  save is started.
- **The flag `time_segment`** (value 1) tints `exterior` zones for dusk.
- **The arena HUD is the second game's:** it prints the game's title in capitals top-left, the Canto plates read "CUERPO",
  "MEMORIA", "VOLUNTAD", and sprite prefixes default to `GG` (player) and `BU` (boss).
- **Order puzzle row icons** are fixed drawings (a rectangle, two hands, three waves) picked by card index.
- **Title fallback:** with no `LOGO` asset and no `title`, the title screen shows the game's `id`.
- `tiles.json` `"atlas"` is ignored: the atlas is always `TS_ATLAS`.
- `meta.json` `frame_ms` must be an array; a plain number is ignored.
- A prop with a `layer` value other than `low`, `top`, `front`, `lit` is never drawn.
- An NPC used with "Usar"/"Mostrar" must have a plain dialogue ID in `dlg` (`"D_X"`, not `"D_X.node"`); the `show`
  map is looked up in that file.
- `on_enter` also runs when a save is loaded in that zone; guard one-time effects with an event and a flag.
- `fade_out` leaves the screen black until a `fade_in` step, another sequence or a screen reset.
- The validator does not check assets, dialogue line `do` effects, choice length, conduit sounds, or the
  title/end `ambient` of music.json.
